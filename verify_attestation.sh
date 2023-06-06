#!/bin/sh
# This script extracts and verifies provenance from the most recent TaskRun.
# Prerequisites:
# - install `cosign` and `jq`.
# - set up Application Default Credentials by running `gcloud auth application-default login`.
set -e

dir=$(dirname $0)
. "${dir}"/env.sh

IMAGE_URL=$(${tkn} tr describe --last -o jsonpath="{.status.results[1].value}")
IMAGE_DIGEST=$(${tkn} tr describe --last -o jsonpath="{.status.results[0].value}")

alias gcurl='curl -s -X GET -H "Content-Type: application/json" -H "Authorization: Bearer $(gcloud auth print-access-token)"'
query_url="https://containeranalysis.googleapis.com/v1/projects/$PROJECT/occurrences?filter=resourceUrl=\"${IMAGE_URL}@${IMAGE_DIGEST}\"%20AND%20kind=\"ATTESTATION\""

TMP=$(mktemp -d)
full=${TMP}/full
gcurl "${query_url}" > ${full}

# This is the signing key.
KEY_REF=$(jq -r '.occurrences[0].envelope.signatures[0].keyid' "${full}")

# Extract the signature.
signature=${TMP}/signature
jq -r '.occurrences[0].envelope.signatures[0].sig' "${full}" | tr '\-_' '+/' | base64 -d > ${signature}

attestation=${TMP}/attestation
jq -r '.occurrences[0].envelope.payload' "${full}" | tr '\-_' '+/' | base64 -d > ${attestation}

# Verify the signature.
cosign verify-blob --insecure-ignore-tlog=true --key "${KEY_REF}" --signature "${signature}" "${attestation}"

rm -rf "${TMP}"
