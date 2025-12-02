# (c) 2025 JFrog Ltd.
# JFrog Token Rotator Lambda for AWS Secret

This repo provides an [AWS Lambda](https://aws.amazon.com/lambda/) function for automatic rotation of [JFrog access tokens](https://jfrog.com/help/r/jfrog-platform-administration-documentation/access-tokens) stored in [AWS Secrets Manager](https://aws.amazon.com/secrets-manager/). It securely generates and rotates short-lived JFrog tokens using your Lambda's IAM role, without manual intervention.

## Overview

This solution lets [AWS ECS](https://aws.amazon.com/ecs/) tasks pull private registry container images using short-lived JFrog tokens, automatically rotated in AWS Secrets Manager by the Lambda function. This removes the need for long-lived, manually rotated tokens.

The [lambda function](./lambda_function.py) performs automatic rotation of JFrog access tokens into the AWS secret by the below lambda events:
1. **Creating:** A new JFrog access token using AWS IAM credentials
2. **Setting:** This step is not needed so function is skipped
3. **Testing:** The new token to ensure it works correctly
4. **Finishing:** the rotation by promoting the new token to current

## How the lambda code Works

### 1. createSecret Step

- Retrieves AWS IAM credentials from the lambda execution role
- Creates a signed request to JFrog's AWS token endpoint
- Exchanges AWS credentials for a JFrog access token
- Stores the new token in Secrets Manager with `AWSPENDING` stage

### 2. testSecret Step

- Performs token test by calling the JFrog access readiness endpoint with the `Authorization` header container the created token

### 3. finishSecret Step

- Promotes the `AWSPENDING` token to `AWSCURRENT`
- Removes the old token version from `AWSCURRENT` stage

## Token Exchange Process

The function uses AWS SigV4 authentication to exchange IAM credentials for JFrog tokens:

## Architecture

The rotation process follows the AWS Secrets Manager's three-step rotation pattern:
```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│ createSecret│ -> │ testSecret  │ -> │finishSecret │
└─────────────┘    └─────────────┘    └─────────────┘
```

## Prerequisites

- The [AWS CLI](https://aws.amazon.com/cli/) configured with the appropriate permissions
- A JFrog Artifactory instance with a JFrog user tagged with IAM Role ARN (see the JFrog user section)
- Python 3.9 or newer
- Required AWS IAM permissions (see IAM Permissions section)

## Limitations

This lambda works on regional STS authentication based on the lambda region

## Environment Variables

The lambda function requires the following environment variables:

| Variable | Description | Required | Example |
|----------|-------------|----------|---------|
| `JFROG_HOST` | JFrog Artifactory hostname | Yes | `mycompany.jfrog.io` |
| `SECRET_TTL` | Token expiration time in seconds | Yes | `21600` |

## Lambda IAM Permissions

The lambda execution role requires the following permissions:

### Secrets Manager Permissions

Lambda permissions should include:
- STS assume role and GetCallerIdentity for allowing the token exchange operation
- secretsmanager secrets operation for allowing the function to get/read and push new secrets
- logs operations for logging lambda troubleshooting messages   
- lambda:GetFunctionConfiguration to allow getting lambda configuration, for example, get lambda ROLE ARN

Notice: The policy below can become more strict by limiting resources permitted, for example: assumed roles, secrest access etc...

# Manual Setup

## 1. Create the lambda IAM role & permissions

```bash
#Create lambda IAM Role
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

## 2. Lambda creation

### 2.1. Package & Push the Lambda Function as a Container Image

```bash
# Build the lambda container image
docker buildx build --platform linux/amd64 --provenance=false -t docker-image:test .

# Upload the docker to AWS ECR

# Login to AWS ECR
aws ecr get-login-password --region <region> | docker login --username AWS --password-stdin <account_id>.dkr.ecr.<region>.amazonaws.com

# Create an ECR repo
aws ecr create-repository --repository-name jfrog-secret-rotator-lambda --region <region> --image-scanning-configuration scanOnPush=true --image-tag-mutability MUTABLE

# Take the repositoryUri from the response and use it to tag the image
docker tag docker-image:test <account_id>.dkr.ecr.<region>.amazonaws.com/jfrog-secret-rotator-lambda:latest

# Push the image to ECR
docker push docker-image:test <account_id>.dkr.ecr.<region>.amazonaws.com/jfrog-secret-rotator-lambda:latest

```

### 2.2 Create the lambda Function with the previously created permissions

```bash
# Create the lambda function from the pushed image and with the IAM role previously created 
aws lambda create-function \
  --function-name jfrog-secret-rotator-lambda \
  --package-type Image \
  --code ImageUri=<account_id>.dkr.ecr.<region>.amazonaws.com/jfrog-secret-rotator-lambda:latest \
  --role arn:aws:iam::<account_id>:role/jfrog_secret_rotation_lambda \
  --environment Variables="{JFROG_HOST=<host>,SECRET_TTL=21600}" \
  --region=<region> \
  --description "JFrog access token rotation based on Lambda IAM role"

# Add Resource-based policy statements to the lambda function with permission policy that grants access to the principal: secretsmanager.amazonaws.com to action: lambda:InvokeFunction, this allows the secret call our lambda function for rotation
aws lambda add-permission \
    --function-name jfrog-secret-rotator-lambda \
    --statement-id secretsmanager-invoke \
    --action lambda:InvokeFunction \
    --principal secretsmanager.amazonaws.com \
    --region=<region>
```

## 3. Configure AWS Secrets Manager secret

```bash
# Create a secret for JFrog token
aws secretsmanager create-secret \
    --name "jfrog/access-token" \
    --region <region> \
    --description "JFrog Artifactory access token" \
    --secret-string '{"token":"any-initial-token-value"}'

# Configure rotation schedule
# Important! rotation schedule MUST be shorter than the SECRET_TTL defined for the lambda function, or the token will expire before a new one is rotated, in this example we use token TTL of 6 hours (21600 seconds) for 4 hours rotation of the AWS secret
aws secretsmanager rotate-secret \
    --secret-id "jfrog/access-token" \
    --region <region> \
    --rotation-lambda-arn "arn:aws:lambda:<region>:<account_id>:function:jfrog-secret-rotator-lambda" \
    --rotation-rules  ScheduleExpression="rate(4 hours)",Duration="4h"
```

### 4. Tag a JFrog user

```bash
# Tag a jfrog user with the lambda IAM Role ARN so the token exchange would return that user's token 
curl -XPUT "https://<jfrog host>/access/api/v1/aws/iam_role" \
     -H "Content-type: application/json" \
     -H "Authorization: Bearer <JFrog admin token>" -d '{"username": "<jfrog username>", "iam_role": "arn:aws:iam::<account_id>:role/jfrog_secret_rotation_lambda"}'

# Validate use is indeed tagged with
curl -XGET  "https://<jfrog host>/access/api/v1/aws/iam_role/<jfrog username>" -H "Authorization: Bearer <JFrog admin token>"
```

## Usage

### Testing Manual Rotation

To manually trigger a rotation:

```bash
# Rotate secret
aws secretsmanager rotate-secret --secret-id "jfrog/access-token"

# Once rotated, you can watch the Cloudwatch logs for log group /aws/lambda/jfrog-secret-rotator-lambda

# Check the rotated secret value using:
aws secretsmanager get-secret-value --secret-id jfrog/access-token --region <region> --version-stage AWSCURRENT
```

### Use with an ECS task

Create an ECS task definition marking the task as pulling from private registry.

Set your image name and JFrog image and tag for example `my-platform.jfrog.io/docker/<DOCKER_IMAGE>:<DOCKER_TAG>`.

Make sure the Task execution role contains permissions to decrypt and get the secret: 
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

## Monitoring and Logging

The function logs important events at each rotation step.

Monitor CloudWatch logs for rotation status and any errors.

# Terraform Setup Example

This repository includes a [Terraform example configuration](./terraform-example/) that automates the setup of the required infrastructure resources.

There is also an optional example of an [ECS cluster](./terraform-example/ecs.tf) and task creation to show how you can also setup your ECS to use the created resources for a seamless integration with JFrog as its private container registry. You enable it with the terraform variable `enable_ecs` (which defaults to `false`).

## What Terraform Does

The Terraform configuration creates a complete end-to-end infrastructure:

1. **Lambda Function & IAM Role** - Deploys Lambda from ECR with IAM permissions for secret rotation.
2. **AWS Secrets Manager** - Creates and rotates a JFrog access token secret automatically.
3. **JFrog Integration** - Assigns the Lambda IAM role to the specified JFrog user via API.
4. **VPC Infrastructure** - Provisions VPC, subnets, gateways, and VPC endpoints for secure networking.
5. **(Optionally) ECS Deployment Example** - Deploys ECS Fargate cluster and nginx service behind an ALB using the secret.

## How to Run

### Prerequisites

- [Terraform](https://terraform.io) >= 1.0 installed
- AWS CLI configured with the appropriate credentials
- ECR image already built and pushed (see section 2.1 for manual setup)
- JFrog admin access token for API authentication

### Step 1: Configure Variables

Edit `terraform-example/terraform.tfvars` with your values:

```hcl
region = "eu-central-1"

ecr_image_uri = "YOUR_ACCOUNT_ID.dkr.ecr.YOUR_REGION.amazonaws.com/jfrog-secret-rotator-lambda:latest"

jfrog_host = "your-company.jfrog.io"

jfrog_admin_username = "your-jfrog-username"

jfrog_admin_token = "your-jfrog-admin-token"

alb_allowed_cidr_blocks = ["YOUR_IP/32"]  # Optional: restrict ALB access

enable_ecs = false

tags = {
  Environment = "Demo"
  Group       = "CTO"
  ManagedBy   = "terraform"
}
```

### Step 2: Initialize Terraform

```bash
cd terraform-example
terraform init
```

### Step 3: Review the Plan

```bash
terraform plan
```

This will show you all resources that will be created. Review the plan carefully.

### Step 4: Apply the Configuration

```bash
terraform apply
```

Terraform will prompt you to confirm. Type `yes` to proceed. The deployment typically takes 10-15 minutes.

### Step 5: Note Important Outputs

After successful deployment, Terraform will output:

- `secret_name`: Name of the created secret
- `secret_arn`: ARN of the secret (useful for ECS task definitions)
- `function_name`: Lambda function name
- `iam_role_arn`: IAM role ARN (used for JFrog user tagging)
- `ecs_service_name`: The ECS cluster name
- `ecs_service_name`: The ECS service name
- `alb_dns_name`: ALB DNS name for accessing the ECS service (if enabled)
- `nginx_endpoint`: Full URL to test the nginx service (if enabled)

## How to Test/Validate

### 1. Verify Secret Rotation

Check if the secret rotation is working:

```bash
# Get the secret name from Terraform outputs
cd terraform
SECRET_NAME=$(terraform output -raw secret_name)
REGION=$(terraform output -raw region 2>/dev/null || echo "eu-central-1")  # Use your region from tfvars

# Manually trigger a rotation
aws secretsmanager rotate-secret --secret-id "$SECRET_NAME" --region "$REGION"

# Wait a few minutes, then check the secret value
aws secretsmanager get-secret-value \
  --secret-id "$SECRET_NAME" \
  --version-stage AWSCURRENT \
  --region "$REGION"
```

### 2. Check Lambda Function Logs

```bash
FUNCTION_NAME=$(terraform output -raw function_name)
REGION=$(terraform output -raw region 2>/dev/null || echo "eu-central-1")  # Use your region from tfvars

# View recent logs
aws logs tail /aws/lambda/$FUNCTION_NAME --follow --region "$REGION"
```

### 3. Verify ECS Service

```bash
CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
SERVICE_NAME=$(terraform output -raw ecs_service_name)
REGION=$(terraform output -raw region 2>/dev/null || echo "eu-central-1")  # Use your region from tfvars

# Check service status
aws ecs describe-services \
  --cluster "$CLUSTER_NAME" \
  --services "$SERVICE_NAME" \
  --region "$REGION"

# Check running tasks
aws ecs list-tasks \
  --cluster "$CLUSTER_NAME" \
  --service-name "$SERVICE_NAME" \
  --region "$REGION"
```

### 4. Test the ALB Endpoint

```bash
# Get the ALB endpoint
ALB_ENDPOINT=$(terraform output -raw nginx_endpoint)

# Test the endpoint
curl "$ALB_ENDPOINT"
```

You should see the nginx welcome page if the service is running correctly and the secret is being used to pull the image from JFrog.

### 5. Verify JFrog User Tagging

```bash
# Get the IAM role ARN from outputs
IAM_ROLE_ARN=$(terraform output -raw iam_role_arn)

# Use values from terraform.tfvars (replace with your actual values)
# JFROG_HOST="your-company.jfrog.io"  # From terraform.tfvars
# JFROG_USERNAME="your-username"     # From terraform.tfvars

# Verify the JFrog user is tagged (replace placeholders with your values)
curl -XGET "https://YOUR_JFROG_HOST/access/api/v1/aws/iam_role/YOUR_JFROG_USERNAME" \
  -H "Authorization: Bearer YOUR_JFROG_ADMIN_TOKEN"
```

### 6. Monitor Secret Rotation

Check CloudWatch metrics for rotation:

```bash
SECRET_ARN=$(terraform output -raw secret_arn)
REGION=$(terraform output -raw region 2>/dev/null || echo "eu-central-1")  # Use your region from tfvars

aws cloudwatch get-metric-statistics \
  --namespace AWS/SecretsManager \
  --metric-name SecretRotation \
  --dimensions Name=SecretId,Value="$SECRET_ARN" \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Sum \
  --region "$REGION"
```

## How to Cleanup

To destroy all resources created by Terraform:

```bash
cd terraform

# Review what will be destroyed
terraform plan -destroy

# Destroy all resources
terraform destroy
```

**Important Notes for Cleanup:**

1. **Secret Recovery Window**: The secret is configured with `recovery_window_in_days = 0`, so it will be deleted immediately when destroyed. If you need to recover it, you have no recovery window.

2. **Dependencies**: Some resources may take time to delete (e.g., NAT Gateway, ALB). Be patient during the destroy process.

3. **Manual Cleanup**: If `terraform destroy` fails or gets stuck, you may need to manually clean up:
   - ECS service and tasks
   - Load balancer and target groups
   - NAT Gateway and Elastic IPs
   - VPC endpoints

4. **JFrog User Tag**: The JFrog user IAM role tag is not automatically removed. If you want to remove it manually:
   ```bash
   curl -XDELETE "https://YOUR_JFROG_HOST/access/api/v1/aws/iam_role/YOUR_JFROG_USERNAME" \
     -H "Authorization: Bearer YOUR_JFROG_ADMIN_TOKEN"
   ```

5. **ECR Image**: The Terraform configuration does not manage the ECR repository or image. You'll need to manually delete the ECR repository if you want to remove it:
   ```bash
   aws ecr delete-repository \
     --repository-name jfrog-secret-rotator-lambda \
     --force \
     --region YOUR_REGION
   ```

# Troubleshooting
### Common Issues

1. **Permission Denied**: Ensure the lambda execution role has all required permissions
2. **Token Exchange Failure**: Verify JFrog host configuration and JFrog user tagging
3. **Secret Not Found**: Check that the secret exists and rotation is enabled
4. **Invalid Token**: Ensure the secret TTL is appropriate for your use case
5. **Invalid Token**: Ensure that the Secret rotation schedule and Token configured TTL are aligned (Token TTL should be longer than secret rotation)
6. **Corrupted Secret Version** remove the secret version, for example:
```bash
 aws secretsmanager update-secret-version-stage \
    --secret-id "jfrog/access-token" \
    --version-stage "AWSPENDING" \
    --remove-from-version-id "version-id-to-remove" 
```

# Security Considerations

- The lambda function uses AWS IAM roles for authentication (no hardcoded credentials)
- Tokens are stored securely in AWS Secrets Manager
- All API calls are signed using AWS SigV4 authentication
- Token TTL and Secret Rotation schedule can be configured based on security requirements

# License

Apache-2.0
