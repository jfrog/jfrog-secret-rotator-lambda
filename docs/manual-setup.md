# Manual setup (AWS CLI & REST API)

Step-by-step deployment using the AWS CLI and JFrog REST API. For Terraform, see [Terraform setup](terraform-setup.md).

## Prerequisites

- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate permissions
- A JFrog Artifactory instance and a JFrog user that will be tagged with the Lambda IAM Role ARN
- Docker (to build and push the Lambda container image)
- Python 3.9 or newer (for local inspection; the runtime image uses the Lambda Python base)

## 1. Create the Lambda IAM role and permissions

```bash
# Create Lambda IAM Role
aws iam create-role \
  --role-name jfrog_secret_rotation_lambda \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "lambda.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }' \
  --description "IAM role for JFrog secret rotation Lambda function"

# Attach the permissions policy
aws iam put-role-policy \
  --role-name jfrog_secret_rotation_lambda \
  --policy-name jfrog_secret_rotation_policy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "secretsmanager:DescribeSecret",
          "secretsmanager:UpdateSecretVersionStage"
        ],
        "Resource": "arn:aws:secretsmanager:*:<account_id>:secret:*"
      },
      {
        "Effect": "Allow",
        "Action": [
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue"
        ],
        "Resource": "<full secret ARN>"
      },
      {
        "Effect": "Allow",
        "Action": [
          "lambda:GetFunctionConfiguration"
        ],
        "Resource": "arn:aws:lambda:*:*:function:*"
      },
      {
        "Effect": "Allow",
        "Action": [
          "sts:GetCallerIdentity",
          "sts:AssumeRole"
        ],
        "Resource": "arn:aws:iam::<account_id>:role/jfrog_secret_rotation_lambda"
      },
      {
        "Effect": "Allow",
        "Action": [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource": "arn:aws:logs:*:*:*"
      }
    ]
  }'
```

The policy can be tightened by limiting resources (assumed roles, specific secrets, etc.).

## 2. Package and push the Lambda image

Build from [`secret-rotator/`](../secret-rotator/):

```bash
# Build the Lambda container image
docker buildx build --platform linux/amd64 --provenance=false \
  -t docker-image:test ./secret-rotator

# Login to AWS ECR
aws ecr get-login-password --region <region> | \
  docker login --username AWS --password-stdin <account_id>.dkr.ecr.<region>.amazonaws.com

# Create an ECR repository
aws ecr create-repository \
  --repository-name jfrog-secret-rotator-lambda \
  --region <region> \
  --image-scanning-configuration scanOnPush=true \
  --image-tag-mutability MUTABLE

# Tag and push
docker tag docker-image:test \
  <account_id>.dkr.ecr.<region>.amazonaws.com/jfrog-secret-rotator-lambda:latest

docker push \
  <account_id>.dkr.ecr.<region>.amazonaws.com/jfrog-secret-rotator-lambda:latest
```

## 3. Create the Lambda function

```bash
aws lambda create-function \
  --function-name jfrog-secret-rotator-lambda \
  --package-type Image \
  --code ImageUri=<account_id>.dkr.ecr.<region>.amazonaws.com/jfrog-secret-rotator-lambda:latest \
  --role arn:aws:iam::<account_id>:role/jfrog_secret_rotation_lambda \
  --environment Variables="{JFROG_HOST=<host>,SECRET_TTL=21600}" \
  --region=<region> \
  --description "JFrog access token rotation based on Lambda IAM role"

# Allow Secrets Manager to invoke the function
aws lambda add-permission \
  --function-name jfrog-secret-rotator-lambda \
  --statement-id secretsmanager-invoke \
  --action lambda:InvokeFunction \
  --principal secretsmanager.amazonaws.com \
  --region=<region>
```

## 4. Configure AWS Secrets Manager

The rotated secret JSON uses `username` and `password` (the JFrog access token is stored as `password`), matching what ECS private registry credentials expect.

```bash
# Create a secret for the JFrog token
aws secretsmanager create-secret \
  --name "jfrog/access-token" \
  --region <region> \
  --description "JFrog Artifactory access token" \
  --secret-string '{"username":"dummy-user","password":"dummy-password"}'

# Configure rotation schedule
# Important: rotation schedule MUST be shorter than SECRET_TTL, or the token
# expires before the next rotation. Example: SECRET_TTL=21600 (6h), rotate every 4h.
aws secretsmanager rotate-secret \
  --secret-id "jfrog/access-token" \
  --region <region> \
  --rotation-lambda-arn "arn:aws:lambda:<region>:<account_id>:function:jfrog-secret-rotator-lambda" \
  --rotation-rules ScheduleExpression="rate(4 hours)",Duration="4h"
```

### Token TTL vs rotation schedule

| Rotation schedule | Minimum `SECRET_TTL` | Recommended `SECRET_TTL` (margin) |
|-------------------|----------------------|-----------------------------------|
| `rate(4 hours)` | `14401` | `21600` (6 hours) |
| `rate(1 hour)` | `3601` | `4680` |

Set `SECRET_TTL` so the JFrog token outlives the Secrets Manager rotation interval.

## 5. Tag a JFrog user with the Lambda IAM role

```bash
curl -XPUT "https://<jfrog host>/access/api/v1/aws/iam_role" \
  -H "Content-type: application/json" \
  -H "Authorization: Bearer <JFrog admin token>" \
  -d '{"username": "<jfrog username>", "iam_role": "arn:aws:iam::<account_id>:role/jfrog_secret_rotation_lambda"}'

# Validate
curl -XGET "https://<jfrog host>/access/api/v1/aws/iam_role/<jfrog username>" \
  -H "Authorization: Bearer <JFrog admin token>"
```

When using Terraform with `assign_jfrog_iam_role = false`, run this step with `terraform output -raw iam_role_arn` after apply. See [Terraform setup](terraform-setup.md#when-assign_jfrog_iam_role--false).

## Usage

### Manual rotation

```bash
aws secretsmanager rotate-secret --secret-id "jfrog/access-token"

# Watch CloudWatch logs: /aws/lambda/jfrog-secret-rotator-lambda

aws secretsmanager get-secret-value \
  --secret-id jfrog/access-token \
  --region <region> \
  --version-stage AWSCURRENT
```

### Use with an ECS task

Create an ECS task definition that pulls from a private registry. Set the image to your JFrog Docker repository, for example `my-platform.jfrog.io/docker/<DOCKER_IMAGE>:<DOCKER_TAG>`.

Ensure the task execution role can read the secret:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "<secret-arn>"
      ]
    }
  ]
}
```

## Monitoring and logging

The function logs each rotation step. Monitor CloudWatch Logs for status and errors.

## Teardown

```bash
# Variables — adjust to match your deployment
REGION="eu-central-1"
ACCOUNT_ID="<account_id>"
SECRET_NAME="jfrog/access-token"
FUNCTION_NAME="jfrog-secret-rotator-lambda"
ROLE_NAME="jfrog_secret_rotation_lambda"
JFROG_HOST="<jfrog host>"
JFROG_USERNAME="<jfrog username>"

# 1. Cancel rotation (if configured)
aws secretsmanager cancel-rotate-secret --secret-id "$SECRET_NAME" --region "$REGION" 2>/dev/null || true

# 2. Delete the secret (immediate; no recovery window)
aws secretsmanager delete-secret \
  --secret-id "$SECRET_NAME" \
  --force-delete-without-recovery \
  --region "$REGION"

# 3. Delete the Lambda function
aws lambda delete-function --function-name "$FUNCTION_NAME" --region "$REGION"

# 4. Delete the inline IAM policy and role
aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name jfrog_secret_rotation_policy
aws iam delete-role --role-name "$ROLE_NAME"

# 5. Optional: delete the ECR repository
aws ecr delete-repository \
  --repository-name jfrog-secret-rotator-lambda \
  --force \
  --region "$REGION"

# 6. Optional: remove the JFrog IAM role tag (not removed automatically)
curl -XDELETE "https://${JFROG_HOST}/access/api/v1/aws/iam_role/${JFROG_USERNAME}" \
  -H "Authorization: Bearer <JFrog admin token>"
```

## Troubleshooting

1. **Permission denied** — Ensure the Lambda execution role has the required Secrets Manager, STS, Logs, and `lambda:GetFunctionConfiguration` permissions.
2. **Token exchange failure** — Verify `JFROG_HOST` and that the JFrog user is tagged with the Lambda IAM role ARN.
3. **Secret not found** — Confirm the secret exists and rotation is enabled.
4. **Invalid / expired token** — Ensure `SECRET_TTL` is longer than the rotation schedule.
5. **Corrupted `AWSPENDING` version** — remove the pending stage, for example:

```bash
aws secretsmanager update-secret-version-stage \
  --secret-id "jfrog/access-token" \
  --version-stage "AWSPENDING" \
  --remove-from-version-id "version-id-to-remove"
```
