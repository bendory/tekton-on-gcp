#!/bin/sh

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

export NODE_POOL=default-pool
export REGION=us-central1
export REPO=my-repo
export LOCATION=us
export BUILDER=builder
export BUILDER_SA="${BUILDER}@${PROJECT}.iam.gserviceaccount.com"
export CHAINS_NS=tekton-chains
export VERIFIER=tekton-chains-controller
export VERIFIER_SA="${VERIFIER}@${PROJECT}.iam.gserviceaccount.com"
export KEY=tekton-signing-key
export KEYRING=tekton-keyring
