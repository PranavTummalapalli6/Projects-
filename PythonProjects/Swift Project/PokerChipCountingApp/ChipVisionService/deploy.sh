#!/bin/bash
# Deploys ChipVisionService to Cloud Run. Without --apply it only PRINTS what it would
# run: creating cloud resources needs a billing account and your login, and is yours to
# decide. Same steps as README.md → Deploying.
#
#   ./deploy.sh              # show the plan
#   ./deploy.sh --apply      # run it (gcloud and firebase must be logged in to the project)
#
# Safe to run again: every step either creates what is missing or updates what is there.
set -euo pipefail

PROJECT="${PROJECT:-pokerchipapp-f7a84}"
REGION="${REGION:-us-central1}"
SERVICE="${SERVICE:-chip-vision-service}"
SA_NAME="chip-vision-runner"
SA="$SA_NAME@$PROJECT.iam.gserviceaccount.com"
REPO="chip-vision"
IMAGE="$REGION-docker.pkg.dev/$PROJECT/$REPO/$SERVICE"
HERE="$(cd "$(dirname "$0")" && pwd)"

APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

run() {
  echo "+ $*"
  if [ "$APPLY" -eq 1 ]; then "$@"; fi
}

# Runs a command and carries on if it fails because the thing already exists.
ensure() {
  echo "+ $*"
  if [ "$APPLY" -eq 1 ]; then
    "$@" || echo "  (already there, or not allowed: carrying on)"
  fi
}

[ "$APPLY" -eq 1 ] || echo "# Dry run: nothing below is executed. Add --apply to run it."

run gcloud services enable run.googleapis.com artifactregistry.googleapis.com \
  cloudbuild.googleapis.com iamcredentials.googleapis.com --project "$PROJECT"

ensure gcloud iam service-accounts create "$SA_NAME" --project "$PROJECT" \
  --display-name "ChipVisionService Cloud Run identity"
for ROLE in roles/storage.objectAdmin roles/datastore.user roles/firebaseauth.admin; do
  run gcloud projects add-iam-policy-binding "$PROJECT" --member "serviceAccount:$SA" --role "$ROLE" --condition=None
done
run gcloud iam service-accounts add-iam-policy-binding "$SA" --project "$PROJECT" \
  --member "serviceAccount:$SA" --role roles/iam.serviceAccountTokenCreator

ensure gcloud artifacts repositories create "$REPO" --repository-format=docker \
  --location="$REGION" --project "$PROJECT"
run gcloud builds submit --tag "$IMAGE" --project "$PROJECT" "$HERE"

# Unauthenticated at Cloud Run's layer on purpose: the service checks a Firebase ID token itself
# (see _bearer_uid in app/main.py) and rate-limits each signed-in user.
run gcloud run deploy "$SERVICE" --image "$IMAGE" --project "$PROJECT" --region "$REGION" \
  --service-account "$SA" --allow-unauthenticated \
  --memory 1Gi --timeout 60 --min-instances 0 --max-instances 3

echo
echo "# Then, once, from the repository root:"
echo "#   firebase deploy --only firestore:rules,firestore:indexes,storage --project $PROJECT"
echo "#   gcloud storage buckets update gs://$PROJECT.firebasestorage.app --lifecycle-file=ChipVisionService/storage-lifecycle.json"
echo "# and create a billing budget with alerts (docs/RELEASE.md, 'Deploy the backend', step 6)."
if [ "$APPLY" -eq 1 ]; then
  echo
  echo "# The service is at:"
  gcloud run services describe "$SERVICE" --project "$PROJECT" --region "$REGION" --format 'value(status.url)'
fi
