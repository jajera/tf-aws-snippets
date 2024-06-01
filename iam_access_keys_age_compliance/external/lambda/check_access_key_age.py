import boto3
import logging
import time
from datetime import datetime, timezone
from botocore.config import Config
from botocore.exceptions import ClientError
import os

logger = logging.getLogger()
logger.setLevel(logging.WARNING)

config = Config(
    retries={
        'max_attempts': 10,
        'mode': 'adaptive'
    }
)

def exponential_backoff(func, max_retries=5, initial_delay=1, max_delay=32):
    retries = 0
    delay = initial_delay

    while retries < max_retries:
        try:
            return func()
        except ClientError as e:
            error_code = e.response['Error']['Code']
            if error_code == 'Throttling':
                logger.warning(f"Throttling warning: {str(e)}. Retrying in {delay} seconds...")
                time.sleep(delay)
                delay = min(delay * 2, max_delay)
                retries += 1
            else:
                logger.error(f"ClientError: {str(e)}")
                raise
    raise Exception(f"Failed after {max_retries} retries due to throttling")

def lambda_handler(event, context):
    try:
        evaluations = []

        iam = boto3.client('iam', config=config)
        config_service = boto3.client('config', config=config)
        max_age = int(os.getenv('MAX_KEY_AGE', 90))
        now = datetime.now(timezone.utc)
        response = exponential_backoff(lambda: iam.list_users())

        for user in response['Users']:
            try:
                keys = exponential_backoff(lambda: iam.list_access_keys(UserName=user['UserName']))
                logger.info(f"UserName: {user['UserName']}")
            except Exception as e:
                logger.error(f"Failed to list access keys for user {user['UserName']} after retries: {str(e)}")
                continue

            for key in keys['AccessKeyMetadata']:
                age = (now - key['CreateDate']).days
                
                if age > max_age:
                    evaluations.append({
                        'ComplianceResourceType': 'AWS::IAM::AccessKey',
                        'ComplianceResourceId': key['AccessKeyId'],
                        'ComplianceType': 'NON_COMPLIANT',
                        'Annotation': (f'Access key age exceeds {max_age} days. '
                                       f'UserName: {user["UserName"]}, '
                                       f'Status: {key["Status"]}, '
                                       f'CreateDate: {key["CreateDate"]}'),
                        'OrderingTimestamp': now
                    })
                else:
                    evaluations.append({
                        'ComplianceResourceType': 'AWS::IAM::AccessKey',
                        'ComplianceResourceId': key['AccessKeyId'],
                        'ComplianceType': 'COMPLIANT',
                        'Annotation': (f'UserName: {user["UserName"]}, '
                                       f'Status: {key["Status"]}, '
                                       f'CreateDate: {key["CreateDate"]}'),
                        'OrderingTimestamp': now
                    })

        exponential_backoff(lambda: config_service.put_evaluations(
            Evaluations=evaluations,
            ResultToken=event['resultToken']
        ))

        logger.info("Evaluation completed successfully")

    except Exception as e:
        logger.error(f"Error: {str(e)}")
        raise
