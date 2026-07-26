# (c) 2026 JFrog Ltd.
# JFrog Secret Rotation Lambda for AWS Secrets Manager
# This lambda function is used to rotate the JFrog access token stored in AWS Secrets Manager
import json
import logging
import os

import boto3
import urllib3
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest

logger = logging.getLogger()
logger.setLevel(logging.INFO)

http = urllib3.PoolManager()

JFROG_HOST = os.environ["JFROG_HOST"]
AWS_TOKEN_ENDPOINT = "/access/api/v1/aws/token"
SECRET_TTL = os.environ["SECRET_TTL"]


# JFROG_HOST may be provided with or without a scheme (e.g. "https://mycompany.jfrog.io"
# or "mycompany.jfrog.io"). Normalize it so we always build valid URLs and pass a bare
# hostname (no scheme, no trailing slash) in the SigV4 "host" header.
def _normalize_jfrog_host(raw_host):
    raw_host = raw_host.strip().rstrip("/")
    if "://" in raw_host:
        scheme, _, host = raw_host.partition("://")
    else:
        scheme, host = "https", raw_host
    return scheme, host


JFROG_SCHEME, JFROG_HOSTNAME = _normalize_jfrog_host(JFROG_HOST)
JFROG_BASE_URL = f"{JFROG_SCHEME}://{JFROG_HOSTNAME}"


def lambda_handler(event, context):
    # return 'Hello from AWS Lambda using Python' + sys.version + '!'
    """Secrets Manager Rotation Template

    This is a template for creating an AWS Secrets Manager rotation lambda

    Args:
        event (dict): Lambda dictionary of event parameters. These keys must include the following:
            - SecretId: The secret ARN or identifier
            - ClientRequestToken: The ClientRequestToken of the secret version
            - Step: The rotation step (one of createSecret, setSecret, testSecret, or finishSecret)

        context (LambdaContext): The Lambda runtime information

    Raises:
        ResourceNotFoundException: If the secret with the specified arn and stage does not exist

        ValueError: If the secret is not properly configured for rotation

        KeyError: If the event parameters do not contain the expected keys

    """
    arn = event["SecretId"]
    token = event["ClientRequestToken"]
    step = event["Step"]
    logger.info(f"Secret rotation step {step} for secret {token} {arn}.")
    # Setup the secret manager client
    service_client = boto3.client("secretsmanager")

    # Make sure the version is staged correctly
    metadata = service_client.describe_secret(SecretId=arn)
    if not metadata["RotationEnabled"]:
        logger.error(f"Secret {arn} is not enabled for rotation")
        raise ValueError(f"Secret {arn} is not enabled for rotation")
    versions = metadata["VersionIdsToStages"]
    if token not in versions:
        logger.error(f"Secret version {token} has no stage for rotation of secret {arn}.")
        raise ValueError(f"Secret version {token} has no stage for rotation of secret {arn}.")
    if "AWSCURRENT" in versions[token]:
        logger.info(f"Secret version {token} already set as AWSCURRENT for secret {arn}.")
        return
    elif "AWSPENDING" not in versions[token]:
        logger.error(f"Secret version {token} not set as AWSPENDING for rotation of secret {arn}.")
        raise ValueError(f"Secret version {token} not set as AWSPENDING for rotation of secret {arn}.")

    if step == "createSecret":
        # Get the function ARN from the context object
        function_arn = context.invoked_function_arn
        create_secret(service_client, arn, token, function_arn)

    elif step == "setSecret":
        set_secret(service_client, arn, token)

    elif step == "testSecret":
        access_token = service_client.get_secret_value(
            SecretId=arn,
            VersionId=token,
            VersionStage="AWSPENDING",
        )["SecretString"]
        # retrieve access token from secret string
        access_token = json.loads(access_token)["password"]
        test_secret(access_token)

    elif step == "finishSecret":
        finish_secret(service_client, arn, token)

    else:
        raise ValueError("Invalid step parameter")


def create_secret(service_client, arn, token, function_arn):
    """Create the secret

    This method first checks for the existence of a secret for the passed in
    token. If one does not exist, it will generate a new secret and put it with
    the passed in token.

    Args:
        service_client (client): The secrets manager service client
        arn (string): The secret ARN or other identifier
        token (string): The ClientRequestToken associated with the secret version
    Raises:
        ResourceNotFoundException: If the secret with the specified arn and stage does not exist
    """
    # Make sure the current secret exists
    service_client.get_secret_value(SecretId=arn, VersionStage="AWSCURRENT")

    # Now try to get the secret version, if that fails, put a new secret
    try:
        service_client.get_secret_value(SecretId=arn, VersionId=token, VersionStage="AWSPENDING")
        logger.info(f"createSecret: Successfully retrieved secret for {arn}.")
    except service_client.exceptions.ResourceNotFoundException:
        # Initialize the Lambda client
        lambda_client = boto3.client("lambda")
        username, access_token = getCredentials(lambda_client, function_arn)
        logger.info(f"createSecret: Successfully got JFrog credentials of username {username}")
        if username is None or access_token is None:
            logger.error("Error getting credentials")
            raise ValueError("Error getting credentials") from None
        secret_string = json.dumps({"username": username, "password": access_token})
        # Put the secret
        service_client.put_secret_value(
            SecretId=arn,
            ClientRequestToken=token,
            SecretString=secret_string,
            VersionStages=["AWSPENDING"],
        )
        logger.info(f"createSecret: Successfully put secret for ARN {arn} and version {token}.")


def set_secret(service_client, arn, token):
    # This is where the secret should be set in the service, but is not required for the JFrog rotation
    # raise NotImplementedError
    logger.info("setSecret: No need to set the secret in the JFrog service")


def test_secret(access_token):
    # This is where the secret can be tested against the JFrog service
    # For the JFrog rotation, we are skipping this test, as the secret is returned by JFrog and therefor is valid
    logger.info("test_secret: JFrog token rotation test")
    readinessURL = f"{JFROG_BASE_URL}/access/api/v1/system/readiness"
    headers = {"Authorization": f"Bearer {access_token}"}
    response = http.request("GET", readinessURL, headers=headers)
    response_text = response.data.decode("utf-8")
    if response.status != 200:
        logger.error(f"JFrog Readiness Check Failed: response.status_code={response.status}, {response_text}")
        raise ValueError(f"JFrog Readiness Check Failed: response.status_code={response.status}, {response_text}")
    else:
        logger.info(f"JFrog Readiness Check Successful: {response_text}")


def finish_secret(service_client, arn, token):
    """Finish the secret
    This method finalizes the rotation process by marking the secret version passed in as the AWSCURRENT secret.
    Args:
        service_client (client): The secrets manager service client
        arn (string): The secret ARN or other identifier
        token (string): The ClientRequestToken associated with the secret version
    Raises:
        ResourceNotFoundException: If the secret with the specified arn does not exist
    """
    # First describe the secret to get the current version
    metadata = service_client.describe_secret(SecretId=arn)
    current_version = None
    for version in metadata["VersionIdsToStages"]:
        if "AWSCURRENT" in metadata["VersionIdsToStages"][version]:
            if version == token:
                # The correct version is already marked as current, return
                logger.info(f"finishSecret: Version {version} already marked as AWSCURRENT for {arn}")
                return
            current_version = version
            break

    # Finalize by staging the secret version current
    service_client.update_secret_version_stage(
        SecretId=arn,
        VersionStage="AWSCURRENT",
        MoveToVersionId=token,
        RemoveFromVersionId=current_version,
    )
    logger.info(f"finishSecret: Successfully set AWSCURRENT stage to version {token} for secret {arn}.")


def getCredentials(lambda_client, function_arn):
    # Create a boto3 session object
    session = boto3.Session()
    # Retrieve the credentials from the session
    credentials = session.get_credentials().get_frozen_credentials()

    # Access the individual fields
    # access_key = credentials.access_key
    # secret_key = credentials.secret_key
    # session_token = credentials.token
    region = session.region_name
    logger.info(f"region={region}")
    try:
        # Retrieve the function configuration
        roleResponse = lambda_client.get_function_configuration(FunctionName=function_arn)
        # Extract the role from the function configuration
        role_arn = roleResponse["Role"]
        logger.info(f"Lambda execution role ARN: {role_arn}")
        # Create the request to AWS STS
        endpoint_url = f"https://sts.{region}.amazonaws.com/"

        params = {"Action": "GetCallerIdentity", "Version": "2011-06-15"}
        # Create the AWSRequest object
        aws_request = AWSRequest(method="GET", url=endpoint_url, params=params, data=None)

        logger.info("Signing the aws_request")
        # Sign the request using SigV4Auth
        SigV4Auth(credentials, "sts", region).add_auth(aws_request)

        logger.info("Adding headers to the request")
        signed_headers = dict(aws_request.headers)
        # Add headers
        signed_headers["host"] = JFROG_HOSTNAME
        signed_headers["content-type"] = "application/json"
        signed_headers["x-amz-region-set"] = region

        # Send the request to JFrog
        tokenExchangeUrl = f"{JFROG_BASE_URL}{AWS_TOKEN_ENDPOINT}?region={region}"
        # create a json body
        body = {"expires_in": SECRET_TTL}
        # get stringified body
        body_str = json.dumps(body)
        logger.info(f"tokenExchangeUrl={tokenExchangeUrl} body_str={body_str}")
        # post http request
        response = http.request("POST", tokenExchangeUrl, headers=signed_headers, body=body_str)
        response_text = response.data.decode("utf-8")
        # print error response
        logger.info(f"response.status_code={response.status}")
        if response.status != 200:
            logger.error(
                "Error exchanging AWS credentials for JFrog token: "
                f"response.status_code={response.status}, {response_text}"
            )
            return None, None
        # parse response.text and extract access_token
        result = json.loads(response_text)
        access_token = result["access_token"]
        username = result["username"]
        # logger.info(f"access_token={access_token}")
        return username, access_token
    except json.JSONDecodeError as e:
        logger.error(f"Error parsing JSON: {e}")
        return None, None
    except Exception as e:
        logger.error(f"Error creating signed request: {e}")
        return None, None
