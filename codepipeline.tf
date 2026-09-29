resource "aws_s3_bucket" "pipeline" {
  bucket        = "${var.name}-pipeline-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}"
  force_destroy = true
  tags          = local.tags
}

resource "aws_s3_bucket_public_access_block" "pipeline" {
  bucket                  = aws_s3_bucket.pipeline.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "pipeline" {
  bucket = aws_s3_bucket.pipeline.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "pipeline" {
  bucket = aws_s3_bucket.pipeline.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_codebuild_project" "test" {
  name          = "${var.name}-test"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 10
  artifacts {
    type = "CODEPIPELINE"
  }
  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:7.0"
    type         = "LINUX_CONTAINER"
  }
  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec-test.yml"
  }
  tags = local.tags
}

resource "aws_codebuild_project" "build" {
  name          = "${var.name}-build"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 20
  artifacts {
    type = "CODEPIPELINE"
  }
  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "PRODUCER_REPOSITORY_URI"
      value = aws_ecr_repository.producer.repository_url
    }
    environment_variable {
      name  = "CONSUMER_REPOSITORY_URI"
      value = aws_ecr_repository.consumer.repository_url
    }
    environment_variable {
      name  = "VALIDATION_HOOK_ARN"
      value = aws_lambda_function.validation.arn
    }
    environment_variable {
      name  = "EXECUTION_ROLE_ARN"
      value = aws_iam_role.ecs_execution.arn
    }
    environment_variable {
      name  = "TASK_ROLE_ARN"
      value = aws_iam_role.consumer.arn
    }
    environment_variable {
      name  = "QUEUE_URL"
      value = aws_sqs_queue.jobs.url
    }
    environment_variable {
      name  = "LOG_GROUP"
      value = aws_cloudwatch_log_group.consumer.name
    }
    environment_variable {
      name  = "TASK_FAMILY"
      value = "${var.name}-consumer"
    }
  }
  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec-build.yml"
  }
  tags = local.tags
}

resource "aws_codebuild_project" "integration" {
  name          = "${var.name}-integration"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 15
  artifacts {
    type = "CODEPIPELINE"
  }
  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:7.0"
    type         = "LINUX_CONTAINER"

    environment_variable {
      name  = "CLUSTER_NAME"
      value = aws_ecs_cluster.this.name
    }
    environment_variable {
      name  = "PRODUCER_TASK_DEFINITION"
      value = aws_ecs_task_definition.producer.family
    }
    environment_variable {
      name  = "SUBNET_IDS"
      value = join(",", var.subnet_ids)
    }
    environment_variable {
      name  = "SECURITY_GROUP_ID"
      value = aws_security_group.consumer.id
    }
    environment_variable {
      name  = "ASSIGN_PUBLIC_IP"
      value = var.assign_public_ip ? "ENABLED" : "DISABLED"
    }
  }
  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec-integration.yml"
  }
  tags = local.tags
}

resource "aws_codepipeline" "this" {
  name          = var.name
  role_arn      = aws_iam_role.codepipeline.arn
  pipeline_type = "V2"

  artifact_store {
    location = aws_s3_bucket.pipeline.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "GitHub"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceOutput"]
      configuration = {
        ConnectionArn    = var.connection_arn
        FullRepositoryId = var.repository_id
        BranchName       = var.branch_name
        DetectChanges    = "true"
      }
    }
  }

  stage {
    name = "Test"
    action {
      name            = "UnitTests"
      category        = "Test"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceOutput"]
      configuration   = { ProjectName = aws_codebuild_project.test.name }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "Containers"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["BuildOutput"]
      configuration    = { ProjectName = aws_codebuild_project.build.name }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "ConsumerBlueGreen"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeployToECS"
      version         = "1"
      input_artifacts = ["BuildOutput"]
      configuration = {
        ApplicationName                = aws_codedeploy_app.consumer.name
        DeploymentGroupName            = aws_codedeploy_deployment_group.consumer.deployment_group_name
        TaskDefinitionTemplateArtifact = "BuildOutput"
        TaskDefinitionTemplatePath     = "taskdef.json"
        AppSpecTemplateArtifact        = "BuildOutput"
        AppSpecTemplatePath            = "appspec.yaml"
        Image1ArtifactName             = "BuildOutput"
        Image1ContainerName            = "IMAGE1_NAME"
      }
    }
  }

  stage {
    name = "Experiment"
    action {
      name            = "StartProducer"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceOutput"]
      configuration   = { ProjectName = aws_codebuild_project.integration.name }
    }
  }

  tags = local.tags
}
