# Build and push the Lambda image

Both deployment paths run the Lambda from a container image in [Amazon ECR](https://aws.amazon.com/ecr/). Build and push the image from [`secret-rotator/`](../secret-rotator/) **before** deploying the Lambda — manually (see [Manual setup](manual-setup.md)) or before `terraform apply` (see [Terraform setup](terraform-setup.md)).

## Prerequisites

- [AWS CLI](https://aws.amazon.com/cli/) configured with permissions to create and push to ECR
- Docker with [`buildx`](https://docs.docker.com/reference/cli/docker/buildx/) (bundled with recent Docker Desktop / Engine)

## Steps

Log in and create the ECR repository first, then build the image tagged with the repository URI and push it in a single `buildx` step:

```bash
# Login to AWS ECR
aws ecr get-login-password --region <region> | \
  docker login --username AWS --password-stdin <account_id>.dkr.ecr.<region>.amazonaws.com

# Create an ECR repository
aws ecr create-repository \
  --repository-name jfrog-secret-rotator-lambda \
  --region <region> \
  --image-scanning-configuration scanOnPush=true \
  --image-tag-mutability MUTABLE

# Build the Lambda container image and push it to ECR in one step
docker buildx build --platform linux/amd64 --provenance=false \
  -t <account_id>.dkr.ecr.<region>.amazonaws.com/jfrog-secret-rotator-lambda:latest \
  --push ./secret-rotator
```

The resulting image URI is:

```
<account_id>.dkr.ecr.<region>.amazonaws.com/jfrog-secret-rotator-lambda:latest
```

Use this URI when creating the Lambda function — as `ImageUri` in [Manual setup Step 4](manual-setup.md#4-create-the-lambda-function), or as the `ecr_image_uri` variable in [Terraform setup](terraform-setup.md).
