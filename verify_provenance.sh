#!/bin/sh
# This script extracts and verifies provenance from the most recent TaskRun.
# Prerequisites:
# - install `cosign` and `jq`.
# - set up Application Default Credentials by running `gcloud auth application-default login`.
# - $PROJECT is set.
set -e

if [[ -z "${PROJECT}" ]]; then
  echo "Set envvar PROJECT to your GCP project before running this script."
  exit 1
fi;

export CLUSTER=tekton-showcase
export REGION=us-central1
export CONTEXT=gke_${PROJECT}_${REGION}_${CLUSTER} # context for kubectl

IMAGE_URL=$(kubectl tkn --context=${CONTEXT} tr describe --last -o jsonpath="{.status.taskResults[1].value}")
IMAGE_DIGEST=$(kubectl tkn --context=${CONTEXT} tr describe --last -o jsonpath="{.status.taskResults[0].value}")

alias gcurl='curl -s -X GET -H "Content-Type: application/json" -H "Authorization: Bearer $(gcloud auth print-access-token)"'
query_url="https://containeranalysis.googleapis.com/v1/projects/$PROJECT/occurrences?filter=resourceUrl=\"${IMAGE_URL}@${IMAGE_DIGEST}\"%20AND%20kind=\"BUILD\""

TMP=$(mktemp -d)
full=${TMP}/full
gcurl "${query_url}" > ${full}

# This is the signing key.
KEY_REF=$(jq -r '.occurrences[0].envelope.signatures[0].keyid' "${full}")

# Extract the signature.
signature=${TMP}/signature
jq -r '.occurrences[0].envelope.signatures[0].sig' "${full}" | tr '\-_' '+/' | base64 -d > ${signature}

# Verify the signature.
cosign verify-blob --key "${KEY_REF}" --signature "${signature}" "${signature}"

rm -rf "${TMP}"
