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

# Location settings
export LOCATION=us
export ZONE=us-central1-c

# Chains configuration
export ATTESTOR_NAME=tekton-chains-attestor
export CHAINS_NS=tekton-chains

# Artifact Registry repo and image
export IMAGE=allow
export REPO=my-repo

# Service Accounts
export BUILDER=builder
export BUILDER_SA="${BUILDER}@${PROJECT}.iam.gserviceaccount.com"
export VERIFIER=tekton-chains-controller
export VERIFIER_SA="${VERIFIER}@${PROJECT}.iam.gserviceaccount.com"

# KMS envvars
# It is a best practice to use a separate project for keys to better enforce
# separation of duties:
# https://cloud.google.com/kms/docs/separation-of-duties
#
# To use a separate project, set KEY_PROJECT before running ./setup.sh.
# Otherwise, we just put the key in the same PROJECT as everything else.
if [[ -z "${KEY_PROJECT}" ]]; then
  # Use the same project for Tekton and key storage.
  export KEY_PROJECT=${PROJECT}
  export KEY=tekton-chains-key
else
  # Keys are stored in a separate project; we name the key after the project
  # that uses it to enable ease of key identification and management in the keys
  # project.
  export KEY=${PROJECT}
fi
export KEYRING=tekton-chains
export KEY_VERSION=1
export KMS_URI="gcpkms://projects/${KEY_PROJECT}/locations/${LOCATION}/keyRings/${KEYRING}/cryptoKeys/${KEY}/cryptoKeyVersions/${KEY_VERSION}"

# kubectl configuration
export PROD_CLUSTER=prod
export PROD_CONTEXT=gke_${PROJECT}_${ZONE}_${PROD_CLUSTER} # context for kubectl
export TEKTON_CLUSTER=tekton
export TEKTON_CONTEXT=gke_${PROJECT}_${ZONE}_${TEKTON_CLUSTER} # context for kubectl

# Pre-requisites: installation of Cloud SDK, kubectl, tkn
gcloud=$(which gcloud)   || ( echo "gcloud not found" && exit 1 )
kubectl=$(which kubectl) || ( echo "kubectl not found" && exit 1 )
tkn=$(which tkn)         || ( echo "tkn not found" && exit 1 )

# Aliases for commands
key_gcloud="${gcloud} --project=${KEY_PROJECT}"
gcloud="${gcloud} --project=${PROJECT}"
tkn="${tkn} --context=${TEKTON_CONTEXT}"
k_tekton="${kubectl} --context=${TEKTON_CONTEXT}"
k_prod="${kubectl} --context=${PROD_CONTEXT}"
