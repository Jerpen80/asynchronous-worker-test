# Terraform AWS Asynchronous Worker

This standalone Terraform project is built around two experiments.

## What I want to test

### 1. A producer and consumer connected by a queue

The first goal is to understand an asynchronous workload end to end:

```text
Producer ECS task -> SQS queue -> Consumer ECS service
                                      |
                              queue-depth autoscaling
```

The producer is an on-demand Fargate task. It sends configurable bursts of messages and exits. The consumer is a long-running Fargate service that receives one message at a time, simulates work, and deletes the message only after successful processing.

This experiment shows:

- the SQS receive, visibility timeout, retry, and delete lifecycle;
- how an unacknowledged message becomes visible again;
- how repeatedly failing messages are moved to a dead-letter queue;
- how `ApproximateNumberOfMessagesVisible` drives ECS step scaling;
- how several consumer tasks process the queue concurrently and scale back in after it drains.

Set `failure_rate` above zero to intentionally fail some jobs and observe retries and the DLQ. Increase `processing_seconds` to keep the queue backed up long enough to watch scaling in CloudWatch and ECS.

The producer load pattern is controlled without code changes:

```hcl
producer_messages_per_burst       = 500
producer_burst_count              = 3
producer_burst_interval_seconds   = 120
producer_batch_delay_seconds      = 0.1
```

That example sends 500 messages, waits two minutes, and repeats twice more. Useful patterns include one large burst to watch scale-out, several spaced bursts to watch scale-in and scale-out repeat, and short intervals that keep pressure on the queue. These values become defaults in the producer task definition and can also be overridden for an individual `aws ecs run-task` invocation.

The approximate producer runtime is:

```text
(burst_count - 1) * burst_interval_seconds
+ burst_count * ceil(messages_per_burst / 10) * batch_delay_seconds
```

SQS accepts ten messages per batch, which explains the division by ten. The supplied experiment values use six bursts of 100 messages at three-minute intervals. That runs for approximately 15 minutes and 6 seconds. Increase `producer_messages_per_burst` to make each burst larger, change `producer_burst_interval_seconds` to control the pause, or change `producer_burst_count` to shorten or extend the experiment.

### 2. CodePipeline with tests and CodeDeploy hooks

The second goal is to understand the distinction between CodePipeline stages, CodeBuild phases, and CodeDeploy lifecycle hooks.

```text
CodePipeline
  Source
    -> Test (CodeBuild: install, pre_build, build, post_build)
    -> Build (Docker build, ECR push, deployment artifacts)
    -> Deploy (ECS blue/green through CodeDeploy)
         -> AfterAllowTestTraffic Lambda hook
         -> canary production traffic shift or rollback
    -> Experiment launch (start the producer task and leave it running in ECS)
```

The unit-test stage publishes a JUnit report. The build stage creates both containers, pushes them to ECR, and passes `taskdef.json`, `appspec.yaml`, and `imageDetail.json` to the deploy stage. CodeDeploy creates a green ECS task set and routes the test listener to it. The `AfterAllowTestTraffic` Lambda hook calls the green consumer's health endpoint and reports success or failure to CodeDeploy. Only successful validation allows the canary production shift to continue; failure triggers rollback.

An SQS consumer has no natural HTTP traffic to shift. The small `/health` endpoint, ALB, and its production/test listeners exist specifically to make the complete ECS blue/green lifecycle observable. Actual jobs still enter through SQS.

After deployment, the experiment stage launches the producer task and waits only until ECS reports it as running. The pipeline then finishes while the producer independently continues its configured burst schedule in Fargate. This exercises the complete path:

```text
commit -> unit test -> container build -> ECR -> blue/green deploy
       -> validation hook -> start producer -> SQS -> autoscaled consumers
```

## What Terraform creates

The stack creates:

- an SQS work queue and dead-letter queue;
- producer and consumer ECR repositories;
- an on-demand producer Fargate task;
- an ECS consumer service that scales from SQS queue depth;
- separate CodePipeline source, unit-test, container-build, blue/green deploy, and experiment-launch stages;
- CodeDeploy blue/green traffic shifting with an `AfterAllowTestTraffic` Lambda validation hook;
- an Application Load Balancer with production and test listeners for the CodeDeploy lifecycle.

The consumer uses SQS's normal receive/process/delete acknowledgement flow. If processing fails, it does not delete the message; the visibility timeout makes it available for retry and SQS eventually moves it to the DLQ.

## Requirements

| Name | Version |
| --- | --- |
| Terraform | >= 1.5.0 |
| AWS provider | >= 5.74.0 |
| Archive provider | >= 2.4.0 |

The archive provider only packages the deployment-validation Lambda. All deployed infrastructure is AWS.

## Usage

```hcl
# terraform.tfvars
aws_profile    = "tn-playground"
aws_region     = "eu-central-1"
connection_arn = "arn:aws:codeconnections:eu-central-1:123456789012:connection/example"
repository_id  = "owner/repository"

name       = "async-worker-lab"
vpc_id     = "vpc-0123456789abcdef0"
subnet_ids = ["subnet-aaaa", "subnet-bbbb"]

consumer_min_capacity = 1
consumer_max_capacity = 10
processing_seconds    = 5

producer_messages_per_burst     = 100
producer_burst_count            = 6
producer_burst_interval_seconds = 180
```

Copy `terraform.tfvars.example` to the ignored `terraform.tfvars` file. The values intended for experimentation—including consumer timing/scaling and the producer burst pattern—belong in that local file.

The AWS provider applies `ManagedBy`, `Project`, and the custom `tags` map as default tags to every resource type that supports AWS tags. Explicit resource tags are merged with those defaults. AWS configuration objects that do not support tagging—such as IAM inline policies, ECR lifecycle policies, SQS redrive policies, and some autoscaling policies—cannot be tagged through Terraform.

## Pipeline and lifecycle

```text
GitHub -> Unit tests -> Build/push both images -> CodeDeploy -> Start producer
                                                    |
                         green task set -> test listener -> Lambda hook
                                                    |
                                      canary production traffic shift
```

The final stage starts the producer task and waits only for it to reach `RUNNING`; it does not wait for the experiment to finish or for the queue to drain. The producer continues for approximately 15 minutes using six bursts of 100 messages. Queue depth above 10 invokes step scaling, and an empty queue later scales the consumer in one task at a time down to `consumer_min_capacity`.

These two experiments intentionally live in one repository so one commit can exercise both the workload and its delivery pipeline.

## Deploy

Terraform cannot use an S3 backend until its bucket exists, so create the backend first from the separate bootstrap root. It uses the requested module pinned to commit `59f17d5e6480e1347e5dd6ea83f200036e4242d8`.

The bootstrap pins AWS provider `4.57.0`, matching the pinned module. It also requires an existing customer-managed KMS key because the module's encryption-enforcement policy is invalid when its KMS ARN input is null.

### 1. Bootstrap the backend

The bootstrap starts with local state because the remote backend does not exist yet:

```shell
terraform -chdir=backend-bootstrap init -reconfigure
terraform -chdir=backend-bootstrap plan -out=backend.tfplan
terraform -chdir=backend-bootstrap apply backend.tfplan
```

This creates:

```text
S3 bucket:      terraform-state-async-worker-lab-489947827123
DynamoDB table: terraform-state-lock-async-worker-lab-489947827123
KMS key:        configured through kms_key_arn
```

Now enable the bootstrap's remote backend and migrate its local state under a separate key:

```shell
cp backend-bootstrap/remote-backend.tf.example backend-bootstrap/remote-backend.tf
terraform -chdir=backend-bootstrap init -migrate-state
```

### 2. Deploy the application

The root [`backend.tf`](backend.tf) contains the complete S3 backend configuration:

```shell
terraform init -reconfigure
terraform plan -out=async-worker.tfplan
terraform apply async-worker.tfplan
```

The configured GitHub connection must already be in `AVAILABLE` state. Pipeline source files must also be committed to the configured branch before expecting the first pipeline execution to pass.

## Cost and cleanup

This lab creates billable Fargate tasks, an Application Load Balancer, CodeBuild jobs, CloudWatch Logs, and S3/ECR storage. Remove it when finished:

```shell
terraform destroy
```

Destroy the application stack before destroying `backend-bootstrap`; otherwise its remote state would become inaccessible.
