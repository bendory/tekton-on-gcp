#!/bin/sh
set -e

# Pre-requisite: PROJECT is defined
# Pre-requisite: ${PROJECT} exists in GCP with billing enabled.
if [[ -z "${PROJECT}" ]]; then
  echo "Set envvar PROJECT to your GCP project before running this script."
  exit 1
fi;

# Pre-requisite: authentication for Cloud SDK
ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
if [[ -z "${ACCOUNT}" ]]; then
  echo "Run 'gcloud auth login' to authenticate on GCP before running this script."
  exit 1
fi;

export CLUSTER=prod
export LOCATION=us
export REGION=us-central1
export REPO=my-repo
export IMAGE=allow
export CONTEXT=gke_${PROJECT}_${REGION}_${CLUSTER} # context for kubectl

# Pre-requisites: installation of Cloud SDK, kubectl, tkn
gcloud=$(which gcloud)   || ( echo "gcloud not found" && exit 1 )
kubectl=$(which kubectl) || ( echo "kubectl not found" && exit 1 )
_=$(which kubectl-tkn)   || ( echo "tkn not found" && exit 1 )

gcloud="${gcloud} --project=${PROJECT}"
tkn="${kubectl} tkn --context=${CONTEXT}"
kubectl="${kubectl} --context=${CONTEXT}"
