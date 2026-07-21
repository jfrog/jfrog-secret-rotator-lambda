# Terraform setup

Infrastructure-as-Code deployment via [`terraform-example/`](../terraform-example/). For step-by-step AWS CLI commands, see [Manual setup](manual-setup.md).

The Terraform example provisions:

- Lambda function (from a pre-pushed ECR image) and IAM role for secret rotation
- AWS Secrets Manager secret with rotation schedule
- **JFrog IAM role tagging** for a JFrog user (when `assign_jfrog_iam_role = true`, the default)
- VPC infrastructure (subnets, gateways, VPC endpoints)
- Optional ECS Fargate + ALB demo (`create_ecs`, default `false`)

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- AWS CLI configured with permissions to create the resources above
- ECR image already built and pushed from [`secret-rotator/`](../secret-rotator/) — see [Build and push the Lambda image](build-and-push-image.md)
- When `assign_jfrog_iam_role = true` (default):
  - A JFrog platform admin access token (`jfrog_admin_token`)
  - An existing JFrog user (`jfrog_admin_username`) to receive the IAM role tag
- When `assign_jfrog_iam_role = false`:
  - An existing JFrog user tagged with the Lambda IAM role — see [When `assign_jfrog_iam_role = false`](#when-assign_jfrog_iam_role--false)

## 1. Build and push the Lambda image

Terraform provisions the Lambda from a pre-existing ECR image; it does **not** build or push it. Before applying, build and push the container image from [`secret-rotator/`](../secret-rotator/) — see [Build and push the Lambda image](build-and-push-image.md). Use the resulting image URI as `ecr_image_uri` in `terraform.tfvars`.

## 2. Quick start

```bash
cd terraform-example
cp terraform.tfvars.example terraform.tfvars   # edit with your values (including ecr_image_uri)
terraform init
terraform plan
terraform apply
```

## Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ecr_image_uri` | yes | — | ECR image URI for the Lambda container |
| `jfrog_host` | yes | — | JFrog hostname (e.g. `mycompany.jfrog.io`) |
| `assign_jfrog_iam_role` | no | `true` | Call JFrog API to tag a user with the Lambda IAM role ARN |
| `jfrog_admin_username` | when `assign_jfrog_iam_role` | `""` | JFrog username for IAM role tagging |
| `jfrog_admin_token` | when `assign_jfrog_iam_role` | `""` | JFrog admin token for the tagging API |
| `unique_id` | no | `demo` | Prefix for resource names |
| `region` | no | `eu-central-1` | AWS region |
| `secret_ttl` | no | `21000` | JFrog token TTL in seconds (must exceed rotation interval) |
| `rotation_schedule_expression` | no | `rate(4 hours)` | Secrets Manager rotation schedule |
| `rotation_duration` | no | `4h` | Rotation window duration |
| `secret_initial_value` | no | dummy username/password JSON | Initial secret string before first rotation |
| `timeout` | no | `300` | Lambda timeout (seconds) |
| `memory_size` | no | `512` | Lambda memory (MB) |
| `create_ecs` | no | `false` | Deploy optional ECS + ALB demo |
| `alb_allowed_cidr_blocks` | no | `["0.0.0.0/0"]` | CIDRs allowed to hit the ALB |
| `vpc_cidr` | no | `10.0.0.0/16` | VPC CIDR |
| `tags` | no | `{}` | Resource tags |

See [`terraform.tfvars.example`](../terraform-example/terraform.tfvars.example) for a starter configuration.

## JFrog IAM role tagging (managed by Terraform)

When `assign_jfrog_iam_role = true` (default), Terraform runs a `local-exec` provisioner that calls:

`PUT /access/api/v1/aws/iam_role` with the Lambda execution role ARN and `jfrog_admin_username`.

Provide credentials via `jfrog_admin_token` and `jfrog_admin_username` in `terraform.tfvars`.

## When `assign_jfrog_iam_role = false`

Set `assign_jfrog_iam_role = false` when the JFrog user is already tagged with the Lambda IAM role (or you will tag it manually).

```hcl
assign_jfrog_iam_role = false
# jfrog_admin_username and jfrog_admin_token are not required
```

### What Terraform still manages

AWS resources (Lambda, secret, rotation, VPC, optional ECS) are always created. Only the JFrog IAM role API call is skipped.

### What you must ensure manually

After `terraform apply`, tag a JFrog user with the Lambda role ARN:

```bash
IAM_ROLE_ARN=$(terraform output -raw iam_role_arn)

curl -XPUT "https://YOUR_JFROG_HOST/access/api/v1/aws/iam_role" \
  -H "Content-type: application/json" \
  -H "Authorization: Bearer YOUR_JFROG_ADMIN_TOKEN" \
  -d "{\"username\": \"YOUR_JFROG_USERNAME\", \"iam_role\": \"${IAM_ROLE_ARN}\"}"
```

See [Tag a JFrog user](manual-setup.md#6-tag-a-jfrog-user-with-the-lambda-iam-role).

### Impact of skipping assignment

- **No JFrog admin token required** for apply
- **`terraform destroy` is AWS-only** for JFrog — an existing IAM role tag is not removed
- **Drift is your responsibility** — Terraform will not detect changes made to the JFrog IAM role mapping outside this module

### Switching between modes

| Transition | Guidance |
|------------|----------|
| `false` → `true` | Set `assign_jfrog_iam_role = true`, provide username and admin token, re-apply |
| `true` → `false` | Set `assign_jfrog_iam_role = false` before destroy if you want to keep the JFrog tag; otherwise remove it manually in JFrog |

## Outputs

| Output | Use |
|--------|-----|
| `secret_name` | Secrets Manager secret name |
| `secret_arn` | Secret ARN (ECS task definitions, IAM) |
| `function_name` | Lambda function name |
| `function_arn` | Lambda function ARN |
| `iam_role_arn` | Lambda IAM role ARN (JFrog user tagging) |
| `assign_jfrog_iam_role` | Whether JFrog tagging is managed by Terraform |
| `jfrog_iam_role_assigned` | Assignment status or skip message |
| `vpc_id` | VPC ID |
| `ecs_cluster_name` | ECS cluster name (or `N/A`) |
| `ecs_service_name` | ECS service name (or `N/A`) |
| `alb_dns_name` | ALB DNS name (or `N/A`) |
| `nginx_endpoint` | Demo nginx URL (or `N/A`) |

## Verify

### 1. Secret rotation

```bash
cd terraform-example
SECRET_NAME=$(terraform output -raw secret_name)
REGION=$(terraform output -raw region 2>/dev/null || echo "eu-central-1")

aws secretsmanager rotate-secret --secret-id "$SECRET_NAME" --region "$REGION"

aws secretsmanager get-secret-value \
  --secret-id "$SECRET_NAME" \
  --version-stage AWSCURRENT \
  --region "$REGION"
```

### 2. Lambda logs

```bash
FUNCTION_NAME=$(terraform output -raw function_name)
REGION=$(terraform output -raw region 2>/dev/null || echo "eu-central-1")

aws logs tail /aws/lambda/$FUNCTION_NAME --follow --region "$REGION"
```

### 3. ECS service (if `create_ecs = true`)

```bash
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
SERVICE_NAME=$(terraform output -raw ecs_service_name)
REGION=$(terraform output -raw region 2>/dev/null || echo "eu-central-1")

aws ecs describe-services \
  --cluster "$CLUSTER_NAME" \
  --services "$SERVICE_NAME" \
  --region "$REGION"
```

### 4. ALB endpoint (if ECS enabled)

```bash
ALB_ENDPOINT=$(terraform output -raw nginx_endpoint)
curl "$ALB_ENDPOINT"
```

### 5. JFrog user tagging

```bash
IAM_ROLE_ARN=$(terraform output -raw iam_role_arn)

curl -XGET "https://YOUR_JFROG_HOST/access/api/v1/aws/iam_role/YOUR_JFROG_USERNAME" \
  -H "Authorization: Bearer YOUR_JFROG_ADMIN_TOKEN"
```

## Cleanup

```bash
cd terraform-example
terraform plan -destroy
terraform destroy
```

**Notes:**

1. The secret uses `recovery_window_in_days = 0` (immediate delete).
2. NAT Gateway / ALB deletion can take several minutes.
3. When `assign_jfrog_iam_role = true`, destroy does **not** remove the JFrog IAM role tag — delete it manually if needed:

```bash
curl -XDELETE "https://YOUR_JFROG_HOST/access/api/v1/aws/iam_role/YOUR_JFROG_USERNAME" \
  -H "Authorization: Bearer YOUR_JFROG_ADMIN_TOKEN"
```

4. Terraform does not manage the ECR repository or image — delete them manually if desired (see [Teardown](manual-setup.md#teardown)).
