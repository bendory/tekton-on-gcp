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

export ATTESTOR_NAME=tekton-chains-attestor
export BUILDER=builder
export BUILDER_SA="${BUILDER}@${PROJECT}.iam.gserviceaccount.com"
export CHAINS_NS=tekton-chains
export IMAGE=allow
export KEY=tekton-chains-key
export KEYRING=tekton-chains
export KEY_VERSION=1
export KMS_URI="gcpkms://projects/${PROJECT}/locations/${LOCATION}/keyRings/${KEYRING}/cryptoKeys/${KEY}/cryptoKeyVersions/${KEY_VERSION}"
export LOCATION=us
export NODE_POOL=default-pool
export REGION=us-central1
export REPO=my-repo
export VERIFIER=tekton-chains-controller
export VERIFIER_SA="${VERIFIER}@${PROJECT}.iam.gserviceaccount.com"

export PROD_CLUSTER=prod
export PROD_CONTEXT=gke_${PROJECT}_${REGION}_${PROD_CLUSTER} # context for kubectl
export TEKTON_CLUSTER=tekton
export TEKTON_CONTEXT=gke_${PROJECT}_${REGION}_${TEKTON_CLUSTER} # context for kubectl

# Pre-requisites: installation of Cloud SDK, kubectl, tkn
gcloud=$(which gcloud)   || ( echo "gcloud not found" && exit 1 )
kubectl=$(which kubectl) || ( echo "kubectl not found" && exit 1 )
_=$(which kubectl-tkn)   || ( echo "tkn not found" && exit 1 )

gcloud="${gcloud} --project=${PROJECT}"
tkn="${kubectl} tkn --context=${TEKTON_CONTEXT}"
k_tekton="${kubectl} --context=${TEKTON_CONTEXT}"
k_prod="${kubectl} --context=${PROD_CONTEXT}"
