#!/bin/sh
# Turn off billing for a Google Cloud project automatically when its budget is exceeded.
#
# Usage: ./setup.sh PROJECT_ID BUDGET_NAME
#   PROJECT_ID   your Google Cloud project, e.g. my-tts-project
#   BUDGET_NAME  billingAccounts/XXXXXX-XXXXXX-XXXXXX/budgets/XXXXXXXX-...
#                (find it with: gcloud billing budgets list --billing-account=XXXXXX-XXXXXX-XXXXXX)
#
# Note: budget alerts can lag behind real spending by hours, so this caps
# runaway costs but is not an exact limit.
set -e
PROJECT=${1:?usage: ./setup.sh PROJECT_ID BUDGET_NAME}
BUDGET=${2:?usage: ./setup.sh PROJECT_ID BUDGET_NAME}
SA=stop-billing@$PROJECT.iam.gserviceaccount.com
cd "$(dirname "$0")"
gcloud config set project "$PROJECT" --quiet

echo "1/6 Enabling the APIs this needs"
gcloud services enable cloudfunctions.googleapis.com run.googleapis.com cloudbuild.googleapis.com \
  eventarc.googleapis.com pubsub.googleapis.com cloudbilling.googleapis.com billingbudgets.googleapis.com

echo "2/6 Creating the stop-billing topic and sending budget updates to it"
gcloud pubsub topics describe stop-billing >/dev/null 2>&1 || gcloud pubsub topics create stop-billing
gcloud billing budgets update "$BUDGET" --notifications-rule-pubsub-topic=projects/$PROJECT/topics/stop-billing --format=none

echo "3/6 Creating the stop-billing service account"
gcloud iam service-accounts describe $SA >/dev/null 2>&1 ||
  gcloud iam service-accounts create stop-billing --display-name="Unlinks billing when over budget"

echo "4/6 Allowing it to unlink billing from this project (and nothing else)"
gcloud projects add-iam-policy-binding $PROJECT --member=serviceAccount:$SA \
  --role=roles/billing.projectManager --condition=None --format=none

echo "5/6 Deploying the function (takes a few minutes)"
gcloud functions deploy stop-billing --gen2 --region=us-central1 --runtime=python312 \
  --source=function --entry-point=stop_billing --trigger-topic=stop-billing \
  --service-account=$SA --trigger-service-account=$SA --set-env-vars=PROJECT_ID=$PROJECT --quiet

echo "6/6 Letting the trigger call the function"
gcloud run services add-iam-policy-binding stop-billing --region=us-central1 \
  --member=serviceAccount:$SA --role=roles/run.invoker --format=none

echo "Done. Billing for $PROJECT will be unlinked if spending passes the budget."
