api_endpoint="us-south.certificate-manager.cloud.ibm.com"
# URL encoded CRN-based instance Id of certificate manager
certmgr_id=""
cis_id=""
domain=""
certificate_name=""
callback_endpoint=""
iam_key=""

iam_token=$(echo $(curl -i -k -X POST \
      --header "Content-Type: application/x-www-form-urlencoded" \
      --data-urlencode "apikey=$iam_key" \
      --data-urlencode "grant_type=urn:ibm:params:oauth:grant-type:apikey" \
      "https://iam.cloud.ibm.com/identity/token") | jq  -r .access_token)

# Order a certificate. You can also order via terraform: https://cloud.ibm.com/docs/terraform?topic=terraform-cert-manager-resources#certmanager-order
curl -X POST -H "Content-Type: application/json" \
     -H "authorization: Bearer $iam_token" \
     -d "{ \"name\":\"$certificate_name\", \"domains\":[ \"$domain\"],  \"dns_provider_instance_crn\": \"$cis_id\", \"auto_renew_enabled\": true }" \
     "https://$api_endpoint/api/v1/$certmgr_id/certificates/order"

# Set notification call back url
curl -X PUT  -H "content-type: application/json" \
     -H "authorization: Bearer $iam_token" \
     -d "{\"type\": \"url\", \"endpoint\": \"$callback_endpoint\", \"is_active\": true}" \
     "https://$api_endpoint/api/v1/instances/$certmgr_id/notifications/channels"