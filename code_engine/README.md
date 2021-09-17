Clone this repo and execute the below commands in the `code_engine` directory.

Some notes about this example.

* This example uses podman for containerization, the much more common Docker should work the same.

* This example uses `ic` as an alias for `ibmcloud`.

* This example uses several `ibmcloud` CLI plugins, if you don't have them the CLI should prompt you to install them.

* This example was made using [fish](https://fishshell.com/). The syntax is slightly different than the much more common [Bash](https://www.gnu.org/software/bash/), particularly regarding string manipulation. Some of the below commands will need to be modified to run on your shell if you're not running fish.
```
ic cr login
ic ce project select -n $PROJECT
podman build -t us.icr.io/$NAMESPACE/cos-service-binding .
podman push us.icr.io/$NAMESPACE/cos-service-binding 
ic resource service-instance-create $COS_INSTANCE_NAME cloud-object-storage standard global
ic resource service-instance $COS_INSTANCE_NAME --output JSON | jq -r '.[].id' | ic cos config crn
ic cos bucket-create --bucket $BUCKET_NAME
set LOCATION (ic cos bucket-location-get --bucket $BUCKET_NAME --output JSON | jq -r '.LocationConstraint' | string replace -- '-standard' '.cloud-object-storage.appdomain.cloud')
set ENDPOINT (string join '' 'https://s3.direct.' $LOCATION)
ic ce configmap create -n $CONFIGMAP --from-literal=COS_BUCKETNAME=$BUCKET_NAME --from-literal=COS_ENDPOINT=$ENDPOINT
ic ce job create -n $JOBNAME --image us.icr.io/$NAMESPACE/cos-service-binding --registry-secret $REGISTRY --env-from-configmap $CONFIGMAP
ic ce job bind -n $JOBNAME --service-instance $COS_INSTANCE_NAME --role Writer --prefix COS
ic ce jobrun submit -n $JOBRUN --job $JOBNAME --wait -a python -a cos_push.py -a 'hello'
ic cos object-get --bucket $BUCKET_NAME --key test-object-from-code-engine object
cat object
```

