#!/usr/bin/env bash

###############################################################################
# A script for creating block and file storage volumes and attaching them to VSIs.
#
# Depends on:
# > jq
#  - To install jq on Mac, run brew install jq
#  - To install jq on Linux, run sudo apt-get install jq
# > One or more VSIs
#
# Creates:
# > A block or file storage volume attached to VSIs
#   - The volume is configured in storage.cfg
#
# More information on jq: https://medium.com/cameron-nokes/working-with-json-in-bash-using-jq-13d76d307c4
#
# Use this script by passing VSI IDs as arguments, for example
# ./attach_storage.sh 85605402 85605408 84647771
# Authorization is via environment variables IBM_CLOUD_USER and IBM_CLOUD_API.
# IBM_CLOUD_API must be a classic infrastucture key.
# Set these in your environment or locally.
###############################################################################

source storage.cfg
vsis="{\"parameters\":[["
for vsi in "$@"; do
  vsis="$vsis{\"id\":$vsi}"
  if [[ $vsi != ${!#} ]]; then
    vsis="$vsis,"
  fi
done
vsis="$vsis]]}"
offering_key="FILE_STORAGE_2"
if [[ $OFFERING == "block" ]]; then
  offering_key="BLOCK_STORAGE_2"
fi
iops_per_gb=$(echo "scale=2;$IOPS/$SIZE" | bc)

iops_per_gb_in_range () {
  local less_than=$(echo "$iops_per_gb <= $2" | bc -l)
  local greater_than=$(echo "$iops_per_gb > $1" | bc -l)
  (( $less_than + $greater_than == 2 ))
}

if iops_per_gb_in_range 0 0.25; then
  tier="0.25"
  tier_key="STORAGE_SPACE_FOR_0_25_IOPS_PER_GB"
elif iops_per_gb_in_range 0.25 2; then
  tier="2"
elif iops_per_gb_in_range 2 4; then
  tier="4"
else
  tier="10"
fi
if [[ -z $tier_key ]]; then
  tier_key="STORAGE_SPACE_FOR_${tier}_IOPS_PER_GB"
fi

url='https://api.softlayer.com/rest/v3.1/'
method='SoftLayer_Location_Datacenter/getDatacenters.json?'
params='objectMask=mask%5Bid%2Cname%5D'
locations=$(curl -s -u $IBM_CLOUD_USER:$IBM_CLOUD_API "$url$method$params" \
  | jq -c '.[]')
for location in $locations; do
  if [[ $LOCATION == $(echo $location | jq --raw-output '.name') ]]; then
    datacenter=$(echo $location | jq '.id')
  fi
done

method='SoftLayer_Product_Package/759/getItemPrices.json?'
params='objectMask=mask%5BpricingLocationGroup%5Blocations%5D%2Citem%5BcapacityMinimum%2CcapacityMaximum%5D%5D'
products=$(curl -s -u $IBM_CLOUD_USER:$IBM_CLOUD_API "$url$method$params" \
  | jq -c '.[]')
printf "%s" "Searching SoftLayer catalog for pricing IDs..." $'\n'
IFS=$'\n'
for product in $products; do
  location=$(echo $product | jq 'has("pricingLocationGroup")')
  key=$(echo $product | jq --raw-output '.item.keyName')
  price=$(echo $product | jq '.id')
  units=$(echo $product | jq --raw-output '.item.units')
  max=$(echo $product | jq --raw-output '.item.capacityMaximum')
  min=$(echo $product | jq --raw-output '.item.capacityMinimum')
  description=$(echo $product | jq --raw-output '.item.description')
  restrictSizeMin=$(echo $product | jq --raw-output '.capacityRestrictionMinimum')
  restrictSizeMax=$(echo $product | jq --raw-output '.capacityRestrictionMaximum')
  category=$(echo $product | jq --raw-output '.item.itemCategory.categoryCode')
  unset IFS
  description_array=(${description})
  iops_per_gb_in_description=${description_array[0]}
  if [[ $location = "false" ]] && [[ $key == "STORAGE_AS_A_SERVICE" ]]; then
    saas_price=$price
    printf "%s" "Found " $key $'\n'
  elif [[ $location = "false" ]] && [[ $key == $offering_key ]]; then
    storage_price=$price
    printf "%s" "Found " $key $'\n'
  elif [[ $TYPE == "performance" ]] &&
    [[ $location = "false" ]] &&
    [[ $units == "GBs" ]] &&
    (( $SIZE < $max )) &&
    (( $SIZE >= $min )) &&
    [[ ${description: -3} == $units ]]; then
    size_price=$price
    printf "%s" "Found " $key $'\n'
  elif [[ $TYPE == "performance" ]] &&
    [[ $location = "false" ]] &&
    [[ $units == "IOPS" ]] &&
    (( $IOPS < $max )) &&
    (( $IOPS >= $min )) &&
    (( $SIZE < $restrictSizeMax )) &&
    (( $SIZE >= $restrictSizeMin )); then
    iops_price=$price
    printf "%s" "Found " $key $'\n'
  elif [[ $TYPE == "endurance" ]] &&
    [[ $location = "false" ]] &&
    [[ $key == $tier_key ]]; then
    size_price=$price
    printf "%s" "Found " $key $'\n'
  elif [[ $TYPE == "endurance" ]] &&
    [[ $location = "false" ]] &&
    [[ $category == "storage_tier_level" ]] &&
    [[ $iops_per_gb_in_description == $tier ]]; then
    iops_price=$price
    printf "%s" "Found " $key $'\n'
  fi
done

if [[ $TYPE == "performance" ]]; then
  order_iops="\"iops\": $IOPS, "
fi
order_params() {
cat <<EOF
{
  "parameters": [{
    "complexType": "SoftLayer_Container_Product_Order_Network_Storage_AsAService",
    "packageId": 759,
    "prices": [
      {"id": $saas_price},
      {"id": $storage_price},
      {"id": $size_price},
      {"id": $iops_price}
    ], 
    "quantity": 1,
    "location": $datacenter,
    "useHourlyPricing": false,
    "volumeSize": $SIZE,
    $order_iops
    "osFormatType": {"keyName": "$OS"}
  }]
}
EOF
}

printf "%s" "Placing order with parameters " $(order_params) $'\n'
method='SoftLayer_Product_Order/placeOrder.json'
order_id=$(curl -s -u $IBM_CLOUD_USER:$IBM_CLOUD_API -X POST -d "$(order_params)" \
  "$url$method" \
  | jq '.orderId')
printf "%s" "Order ID is " $order_id $'\n'

order_status=""
volume_id=""
nas=""
params="objectFilter=\{%22networkStorage%22:\{%22billingItem%22:\{%22orderItem%22:\{%22order%22:\{%22id%22:\{%22operation%22:${order_id}\}\}\}\}\}\}"
### Check for storage order status ####
# for block: $nas=ISCSI
# file: $nas=NAS
while [[ $order_status != "APPROVED" ]] ||
  [[ ! $volume_id =~ ^[0-9]+$ ]] ||
  [[ $nas != "ISCSI" && $nas != "NAS" ]]; do
  printf "%s" "Checking order status..." $'\n'
  sleep 60
  method="SoftLayer_Billing_Order/${order_id}/getObject.json"
  order_status=$(curl -s -u $IBM_CLOUD_USER:$IBM_CLOUD_API "$url$method" \
    | jq --raw-output '.status')
  method='SoftLayer_Account/getNetworkStorage.json?'
  volume=$(curl -s -u $IBM_CLOUD_USER:$IBM_CLOUD_API "$url$method$params")
  volume_id=$(echo $volume | jq '.[0].id')
  nas=$(echo $volume | jq --raw-output '.[0].nasType')
  printf "%s" "Order is " $order_status $'\n'
  printf "%s" "Volume is " $volume_id $'\n'
  printf "%s" "NAS type is " $nas $'\n'
done
printf "%s" "New " $OFFERING " volume created with ID " $volume_id $'\n'

ready_to_mount=""
method="SoftLayer_Network_Storage/${volume_id}/getObject.json?"
params='objectMask=mask%5BisReadyToMount%5D'
while [[ $ready_to_mount != "true" ]]; do
  printf "%s" "Waiting for volume to be ready to mount..." $'\n'
  sleep 60
  ready_to_mount=$(curl -s -u $IBM_CLOUD_USER:$IBM_CLOUD_API "$url$method$params" \
    | jq '.isReadyToMount')
done

method="SoftLayer_Network_Storage/${volume_id}/allowAccessFromVirtualGuestList.json"
params='objectMask=mask%5BallowedVirtualGuests%5BallowedHost%5Bcredential%5D%5D%5D'
authorized=$(curl -s -u $IBM_CLOUD_USER:$IBM_CLOUD_API -X POST -d "$vsis" "$url$method")
if [[ $authorized = "true" ]] && [[ $OFFERING == "block" ]]; then
  printf "%s" "Successfully authorized access for VSIs " "$@" $'\n' $'\n'
  method="SoftLayer_Network_Storage_Iscsi/${volume_id}/getObject.json?"
  authorizations=$(curl -s -u $IBM_CLOUD_USER:$IBM_CLOUD_API "$url$method$params" \
    | jq -c '.allowedVirtualGuests')
  guests=$(echo $authorizations | jq -c '.[]')
  for guest in $guests; do
    printf "%s" "hostname (IQN):" $(echo $guest | jq '.allowedHost.name') $'\n'
    printf "%s" "username:" $(echo $guest | jq '.allowedHost.credential.username') $'\n'
    printf "%s" "password:" $(echo $guest | jq '.allowedHost.credential.password') $'\n' $'\n'
  done
elif [[ $authorized = "true" ]] && [[ $OFFERING == "file" ]]; then
  method="SoftLayer_Network_Storage/${volume_id}/getFileNetworkMountAddress.json"
  mount=$(curl -s -u $IBM_CLOUD_USER:$IBM_CLOUD_API "$url$method")
  printf "%s" "mount address:" $mount $'\n'
else
  printf "%s" $authorized
  exit 1
fi
