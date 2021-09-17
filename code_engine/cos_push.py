import sys, os, ibm_boto3
from ibm_botocore.client import Config
from pprint import pprint

cos = ibm_boto3.client(
    service_name="s3",
    ibm_api_key_id=os.environ["COS_APIKEY"],
    ibm_service_instance_id=os.environ["COS_RESOURCE_INSTANCE_ID"],
    ibm_auth_endpoint="https://iam.cloud.ibm.com/identity/token",
    config=Config(signature_version="oauth"),
    endpoint_url=os.environ["COS_ENDPOINT"],
)
response = cos.put_object(
    Bucket=os.environ["COS_BUCKETNAME"],
    Body=sys.argv[1].encode("utf-8"),
    Key="test-object-from-code-engine",
)
pprint(response)
# print(sys.argv[1])
