"""Cloud Function: unlink billing from a project when its budget is exceeded.

Triggered by Pub/Sub budget notifications. PROJECT_ID is set at deploy time
by setup.sh. Unlinking billing stops all paid services in that project.
"""
import base64
import json
import os

import functions_framework
from googleapiclient import discovery

PROJECT_ID = os.environ["PROJECT_ID"]


@functions_framework.cloud_event
def stop_billing(cloud_event):
    data = json.loads(base64.b64decode(cloud_event.data["message"]["data"]))
    if data["costAmount"] <= data["budgetAmount"]:
        return
    billing = discovery.build("cloudbilling", "v1", cache_discovery=False)
    billing.projects().updateBillingInfo(
        name="projects/" + PROJECT_ID, body={"billingAccountName": ""}
    ).execute()
    print("Billing disabled: cost {} > budget {}".format(data["costAmount"], data["budgetAmount"]))
