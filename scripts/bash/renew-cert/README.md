This is an example of how to order an auto-renew certificate, set up callback url for notification about expiring certificate, and use cloud function to auto-renew secret in IKS.

1. Set up a cloud function using `auto_renew.js`. The cloud function requires 4 parameters:

`iam_key`: Your IAM API key.

`region`: region of API endpoint, eg: us-south.

`cluster_id`: ID of IKS cluster.

`certmgr_id`: URL encoded crn id of certificate manager instance.

You can use command:

`ibmcloud fn action create $PACKAGE_NAME/$ACTION_NAME auto_renew.js --kind nodejs:10 --param ${paramName} ${paramValue} --web true`

2. Order an auto-renew certificate and set up callback url using `order_cert.sh`. Specify `callback_endpoint` with the cloud function url that you create in the first step (You can use `ibmcloud fn action get <action_name> --url` to get the url).

Reference:

1. Auto-renewing certificate: https://cloud.ibm.com/docs/certificate-manager?topic=certificate-manager-automating-deployments

2. API for updating IKS certificate secret: https://containers.cloud.ibm.com/global/swagger-global-api/#/alb-beta/UpdateALBSecret
