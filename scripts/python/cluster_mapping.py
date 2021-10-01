import requests
import os
from pprint import pprint

APIKEY = "xxx"
token = None


def _auth():
    global token
    if not token:
        r = requests.post(
            "https://iam.cloud.ibm.com/identity/token",
            auth=("bx", "bx"),
            data={
                "apikey": os.environ["apikey"],
                "grant_type": "urn:ibm:params:oauth:grant-type:apikey",
            },
        )
        token = r.json()["access_token"]
    return {"Authorization": "Bearer " + token}


def _containers(method, params=None):
    r = requests.get(
        "https://containers.cloud.ibm.com/global/v2/vpc/" + method,
        headers=_auth(),
        params=params,
    )
    if r.status_code < 400:
        return r.json()
    else:
        pprint(r.json())
        return None


def _get_workers(cluster):
    r = requests.get(
        "https://containers.cloud.ibm.com/global/v2/vpc/getWorkers",
        headers=_auth(),
        params={"cluster": "c3aba5pd03htm5q8tsng"},
    )


def _map_worker(worker):
    return (worker["id"], worker["networkInterfaces"][0]["ipAddress"])


def _map_cluster(mapping, cluster):
    workers = _containers("getWorkers", params={"cluster": cluster["id"]})
    mapping[cluster["id"]] = []
    try:
        for worker in workers:
            mapping[cluster["id"]].append(_map_worker(worker))
    except TypeError:
        print(workers)


def get_clusters():
    clusters = _containers("getClusters")
    mapping = {}
    for cluster in clusters:
        _map_cluster(mapping, cluster)
    return mapping


if __name__ == "__main__":
    print(
        "This is a dict where the keys are cluster IDs and each one is mapped to VSIs in the cluster."
    )
    r = requests.get(
        "https://accounts.cloud.ibm.com/coe/v2/accounts",
        headers=_auth(),
    )
    account = r.json()["resources"][0]["metadata"]["guid"]
    account_name = r.json()["resources"][0]["entity"]["name"]
    print(f"These are clusters for account {account}, {account_name}.")
    pprint(get_clusters())
