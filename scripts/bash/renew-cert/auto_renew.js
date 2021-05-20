const { promisify } = require("bluebird");
const request = promisify(require("request"));
const jwtVerify = promisify(require("jsonwebtoken").verify);

// Get public key of the certificate manager instance to verify payload
async function getPublicKey(params) {
  const keysOptions = {
    method: "GET",
    url: `https://${params.region}.certificate-manager.cloud.ibm.com/api/v1/instances/${params.certmgr_id}/notifications/publicKey?keyFormat=pem`,
    headers: {
      "cache-control": "no-cache",
    },
  };
  const keysResponse = await request(keysOptions);
  return JSON.parse(keysResponse.body).publicKey;
}

async function getIamToken(params) {
  const options = {
    method: "POST",
    url: "https://iam.cloud.ibm.com/identity/token",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    qs: {
      grant_type: "urn:ibm:params:oauth:grant-type:apikey",
      apikey: params.iam_key,
    },
  };
  const response = await request(options);
  return JSON.parse(response.body).access_token;
}

// Update secret in IKS. https://containers.cloud.ibm.com/global/swagger-global-api/#/alb-beta/UpdateALBSecret
async function updateCertificate(iamToken, certCrn, clusterID, secretName) {
  const options = {
    method: "PUT",
    url: "https://containers.cloud.ibm.com/global/v1/alb/albsecrets",
    headers: {
      "Content-Type": "application/json",
      Authorization: "Bearer " + iamToken,
    },
    body: {
      albSecretConfig: {
        certCrn: certCrn,
        clusterID: clusterID,
        secretName: secretName,
        state: "update_true",
      },
    },
    json: true,
  };
  const response = await request(options);
  console.log(secretName + ": " + response.statusMessage);
}

async function main(params) {
  try {
    const publicKey = await getPublicKey(params);
    const iamToken = await getIamToken(params);
    const decodedNotification = await jwtVerify(params.data, publicKey);
    if (decodedNotification.event_type === "cert_renewed") {
      decodedNotification.certificates.forEach(cert => {
        if (cert.auto_renewed)
          await updateCertificate(iamToken, cert.cert_crn, params.cluster_id, cert.name);
        else
          console.log("This certificated expired. But it's not auto-renewed: " + cert.cert_crn);
      });
    }
    if (decodedNotification.event_type === "cert_about_to_expire_renew_required") {
      decodedNotification.certificates.forEach(cert => {
        console.log("This certificate will expire soon: " + cert.cert_crn);
      });
    }
  } catch (err) {
    console.log(err);
  }
}
