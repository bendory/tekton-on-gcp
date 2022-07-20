#!/bin/sh
# This script extracts and verifies provenance from the most recent TaskRun.
# Prerequisites:
# - install `cosign` and `jq`.
# - set up Application Default Credentials by running `gcloud auth application-default login`.
# - $PROJECT is set.
#set -e

if [[ -z "${PROJECT}" ]]; then
  echo "Set envvar PROJECT to your GCP project before running this script."
  exit 1
fi;

IMAGE_URL=$(tkn tr describe --last -o jsonpath="{.status.taskResults[1].value}")
IMAGE_DIGEST=$(tkn tr describe --last -o jsonpath="{.status.taskResults[0].value}")

alias gcurl='curl -s -X GET -H "Content-Type: application/json" -H "Authorization: Bearer $(gcloud auth print-access-token)"'
query_url="https://containeranalysis.googleapis.com/v1/projects/$PROJECT/occurrences?filter=resourceUrl=\"${IMAGE_URL}@${IMAGE_DIGEST}\"%20AND%20kind=\"ATTESTATION\""

TMP=$(mktemp -d)
full=${TMP}/full
gcurl "${query_url}" > ${full}

# This is the signing key.
KEY_REF=$(cat "${full}" | jq -r '.occurrences[0].envelope.signatures[0].keyid')

# Extract the signature.
signature=${TMP}/signature
cat "${full}" | jq -r '.occurrences[0].envelope.signatures[0].sig' | tr '\-_' '+/' | base64 -d > ${signature}

attestation=${TMP}/attestation
cat "${full}" | jq -r '.occurrences[0].envelope.payload' | tr '\-_' '+/' | base64 -d > ${attestation}

# Verify the signature.
cosign verify-blob --key "${KEY_REF}" --signature "${signature}" "${attestation}"

rm -rf "${TMP}"
