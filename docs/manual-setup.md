# Manual setup (AWS CLI & REST API)

Step-by-step deployment using the AWS CLI and JFrog REST API. For Terraform, see [Terraform setup](terraform-setup.md).

## Prerequisites

- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate permissions
- A JFrog Artifactory instance and a JFrog user that will be tagged with the Lambda IAM Role ARN
- `zip` (standard on macOS/Linux; used by the build script)

The steps below follow the resource dependency order: the Lambda zip is built first (the function requires it), the secret is created next so its ARN can be referenced by the IAM policy, then the role and function are created, and rotation is configured once the function exists.

## 1. Build the Lambda zip

The Lambda runs as a **Python zip** on the managed `python3.14` runtime (handler `lambda_function.lambda_handler`). The managed runtime provides `boto3`, `botocore`, and `urllib3`, so the zip contains only [`lambda_function.py`](../secret-rotator/lambda_function.py).

From the repository root:

```bash
./scripts/build-lambda-zip.sh
```

The script writes `build/jfrog-secret-rotator-lambda.zip` with `lambda_function.py` at the **archive root** so the handler path `lambda_function.lambda_handler` resolves. The resulting archive is used as `--zip-file` when creating the Lambda function in [Step 4](#4-create-the-lambda-function).

> Terraform does not use this script — the [Terraform setup](terraform-setup.md) packages the same file with the [`archive_file`](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) data source. If you add dependencies that are not in the managed runtime, extend both packaging paths to vendor them (for example with `pip install -t` before zipping).

## 2. Create the AWS Secrets Manager secret

The rotated secret JSON uses `username` and `password` (the JFrog access token is stored as `password`), matching what ECS private registry credentials expect.

```bash
# Create a secret for the JFrog token
aws secretsmanager create-secret \
  --name "jfrog/access-token" \
  --region <region> \
  --description "JFrog Artifactory access token" \
  --secret-string '{"username":"dummy-user","password":"dummy-password"}'
```

The `create-secret` response includes the full secret ARN (name plus a random 6-character suffix), for example:

```
arn:aws:secretsmanager:<region>:<account_id>:secret:jfrog/access-token-a1B2c3
```

Note this ARN — it is used as `<full secret ARN>` in the IAM policy in the next step. Rotation is configured later in [Step 5](#5-configure-secret-rotation), after the Lambda function exists.

## 3. Create the Lambda IAM role and permissions

Use the secret ARN from Step 2 as `<full secret ARN>` below.

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

> **`<full secret ARN>`** is the ARN returned by `create-secret` in [Step 2](#2-create-the-aws-secrets-manager-secret). If you prefer not to copy the exact ARN, you can use a wildcard suffix instead: `arn:aws:secretsmanager:<region>:<account_id>:secret:jfrog/access-token-*`.

## 4. Create the Lambda function

```bash
aws lambda create-function \
  --function-name jfrog-secret-rotator-lambda \
  --runtime python3.14 \
  --handler lambda_function.lambda_handler \
  --zip-file fileb://build/jfrog-secret-rotator-lambda.zip \
  --role arn:aws:iam::<account_id>:role/jfrog_secret_rotation_lambda \
  --environment Variables="{JFROG_HOST=<host>,SECRET_TTL=21600}" \
  --region <region> \
  --description "JFrog access token rotation based on Lambda IAM role"

# Allow Secrets Manager to invoke the function
aws lambda add-permission \
  --function-name jfrog-secret-rotator-lambda \
  --statement-id secretsmanager-invoke \
  --action lambda:InvokeFunction \
  --principal secretsmanager.amazonaws.com \
  --region <region>
```

## 5. Configure secret rotation

With the function created and allowed to be invoked by Secrets Manager, attach the rotation schedule to the secret from Step 2.

```bash
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

## 6. Tag a JFrog user with the Lambda IAM role

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

### Testing and verifying rotation

This function is a **Secrets Manager rotation** Lambda. AWS invokes it with `SecretId`, `ClientRequestToken`, and `Step` (`createSecret`, `setSecret`, `testSecret`, or `finishSecret`). It is not meant to be called with an empty or generic test event.

**Do not use the Lambda console “Test” button with `{}` or a default event.** That causes `KeyError: 'SecretId'` because those fields are missing.

**Recommended: trigger a real rotation** (after [Step 5](#5-configure-secret-rotation) and [Step 6](#6-tag-a-jfrog-user-with-the-lambda-iam-role)):

```bash
aws secretsmanager rotate-secret \
  --secret-id "jfrog/access-token" \
  --region <region>
```

Secrets Manager runs all four rotation steps in order and passes the correct payload on each invocation.

**Check that it worked:**

1. **CloudWatch Logs** — Log group `/aws/lambda/jfrog-secret-rotator-lambda`. Look for lines such as `Secret rotation step createSecret` through `finishSecret`, and `JFrog Readiness Check Successful` on the test step. Errors (permissions, JFrog token exchange, readiness) appear here with stack traces.

   ```bash
   aws logs tail /aws/lambda/jfrog-secret-rotator-lambda --follow --region <region>
   ```

2. **Secret value** — Confirm `AWSCURRENT` has a non-dummy `username` / `password` (token):

   ```bash
   aws secretsmanager get-secret-value \
     --secret-id jfrog/access-token \
     --region <region> \
     --version-stage AWSCURRENT
   ```

3. **Rotation state** — Ensure rotation is enabled and version stages look sane (`AWSCURRENT` on the new version; no stuck `AWSPENDING` unless a rotation is in progress):

   ```bash
   aws secretsmanager describe-secret \
     --secret-id jfrog/access-token \
     --region <region>
   ```

**Lambda console test (optional, limited):** If you must test from the console, use an event shaped like Secrets Manager sends. `ClientRequestToken` must match a secret version that is staged as `AWSPENDING`, or the handler will reject the invocation. Prefer `rotate-secret` instead.

```json
{
  "SecretId": "arn:aws:secretsmanager:<region>:<account_id>:secret:jfrog/access-token-XXXXXX",
  "ClientRequestToken": "<uuid-from-describe-secret>",
  "Step": "createSecret"
}
```

### Manual rotation

```bash
aws secretsmanager rotate-secret \
  --secret-id "jfrog/access-token" \
  --region <region>
```

See [Testing and verifying rotation](#testing-and-verifying-rotation) for CloudWatch and secret checks.

```bash
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

The function logs each rotation step. For testing and verification commands, see [Testing and verifying rotation](#testing-and-verifying-rotation). Monitor CloudWatch Logs for status and errors.

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

# 5. Optional: remove the JFrog IAM role tag (not removed automatically)
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
