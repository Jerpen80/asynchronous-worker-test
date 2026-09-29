resource "aws_iam_role" "ecs_execution" {
  name = "${var.name}-ecs-execution"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ecs-tasks.${data.aws_partition.current.dns_suffix}" } }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "consumer" {
  name = "${var.name}-consumer"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ecs-tasks.${data.aws_partition.current.dns_suffix}" } }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "consumer" {
  name = "sqs-consume"
  role = aws_iam_role.consumer.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:GetQueueAttributes"]
      Resource = aws_sqs_queue.jobs.arn
    }]
  })
}

resource "aws_iam_role" "producer" {
  name = "${var.name}-producer"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ecs-tasks.${data.aws_partition.current.dns_suffix}" } }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "producer" {
  name = "sqs-produce"
  role = aws_iam_role.producer.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["sqs:SendMessage"], Resource = aws_sqs_queue.jobs.arn }]
  })
}

resource "aws_iam_role" "codedeploy" {
  name = "${var.name}-codedeploy"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "codedeploy.${data.aws_partition.current.dns_suffix}" } }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "codedeploy" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSCodeDeployRoleForECS"
}

resource "aws_iam_role_policy" "codedeploy_hook" {
  name = "invoke-validation-hook"
  role = aws_iam_role.codedeploy.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "lambda:InvokeFunction", Resource = aws_lambda_function.validation.arn }]
  })
}

resource "aws_iam_role" "codebuild" {
  name = "${var.name}-codebuild"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "codebuild.${data.aws_partition.current.dns_suffix}" } }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "codebuild" {
  name = "build-test-and-push"
  role = aws_iam_role.codebuild.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "*" },
      {
        Effect = "Allow"
        Action = [
          "codebuild:CreateReportGroup",
          "codebuild:CreateReport",
          "codebuild:UpdateReport",
          "codebuild:BatchPutTestCases",
          "codebuild:BatchPutCodeCoverages"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:codebuild:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:report-group/${var.name}-test-*"
      },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"], Resource = "${aws_s3_bucket.pipeline.arn}/*" },
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      {
        Effect   = "Allow"
        Action   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage"]
        Resource = [aws_ecr_repository.producer.arn, aws_ecr_repository.consumer.arn]
      },
      { Effect = "Allow", Action = ["ecs:RunTask", "ecs:DescribeTasks"], Resource = aws_ecs_task_definition.producer.arn },
      { Effect = "Allow", Action = ["ecs:DescribeTasks"], Resource = "*" },
      { Effect = "Allow", Action = "iam:PassRole", Resource = [aws_iam_role.ecs_execution.arn, aws_iam_role.producer.arn] }
    ]
  })
}

resource "aws_iam_role" "codepipeline" {
  name = "${var.name}-codepipeline"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "codepipeline.${data.aws_partition.current.dns_suffix}" } }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "codepipeline" {
  name = "pipeline-actions"
  role = aws_iam_role.codepipeline.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["codestar-connections:UseConnection"], Resource = var.connection_arn },
      { Effect = "Allow", Action = ["s3:GetBucketVersioning", "s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"], Resource = [aws_s3_bucket.pipeline.arn, "${aws_s3_bucket.pipeline.arn}/*"] },
      { Effect = "Allow", Action = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"], Resource = [aws_codebuild_project.test.arn, aws_codebuild_project.build.arn, aws_codebuild_project.integration.arn] },
      { Effect = "Allow", Action = ["codedeploy:CreateDeployment", "codedeploy:GetApplication", "codedeploy:GetApplicationRevision", "codedeploy:GetDeployment", "codedeploy:GetDeploymentConfig", "codedeploy:RegisterApplicationRevision"], Resource = "*" },
      { Effect = "Allow", Action = ["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"], Resource = "*" },
      {
        Effect   = "Allow"
        Action   = "ecs:TagResource"
        Resource = "arn:${data.aws_partition.current.partition}:ecs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:task-definition/${var.name}-consumer:*"
        Condition = {
          StringEquals = { "ecs:CreateAction" = "RegisterTaskDefinition" }
        }
      },
      { Effect = "Allow", Action = "iam:PassRole", Resource = [aws_iam_role.ecs_execution.arn, aws_iam_role.consumer.arn] }
    ]
  })
}

resource "aws_iam_role" "validation" {
  name = "${var.name}-validation-hook"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "lambda.${data.aws_partition.current.dns_suffix}" } }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "validation" {
  name = "validate-and-report"
  role = aws_iam_role.validation.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "*" },
      { Effect = "Allow", Action = ["elasticloadbalancing:DescribeTargetHealth"], Resource = "*" },
      { Effect = "Allow", Action = ["codedeploy:PutLifecycleEventHookExecutionStatus"], Resource = "*" }
    ]
  })
}
