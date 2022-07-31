#!/bin/sh
# This script will deploy ${IMAGE} to ${PROD_CLUSTER} and demonstrate binauth
# enforcement by attempting to deploy a blocked image.
set -e

dir=$(dirname $0)
. "${dir}"/../env.sh

REPO="${LOCATION}-docker.pkg.dev/${PROJECT}/${REPO}"

# BUG: There is currently a mismatch between Tekton Chains and binauthz.  Tekton
# Chains creates a signed attestation matching an image name without a protocol
# prefix, such as:
#    `us-docker.pkg.dev/bendory-20220729-a/my-repo/allow@sha256:35d9febc18674d910ad3945a93fb3bf61fee4f36bca2a6cb80e19b48f7e587db`
#
# Binauthz looks for a signed attestation matching an image name that includes a
# protocol prefix, such as:
#    `https://us-docker.pkg.dev/bendory-20220729-a/my-repo/allow@sha256:35d9febc18674d910ad3945a93fb3bf61fee4f36bca2a6cb80e19b48f7e587db`
#
# To work around this issue, we manually sign the image before deployment.

export CONTAINER_PATH=$(${gcloud} container binauthz attestations list --attestor=tekton-chains-attestor --format='value(resourceUri)' | fgrep allow)

${gcloud} beta container binauthz attestations sign-and-create \
    --artifact-url="${CONTAINER_PATH}" \
    --attestor="${ATTESTOR_NAME}" \
    --attestor-project="${PROJECT}" \
    --keyversion-project="${PROJECT}" \
    --keyversion-location="${LOCATION}" \
    --keyversion-keyring="${KEYRING}" \
    --keyversion-key="${KEY}" \
    --keyversion=1

# This deployment is allowed.
${k_prod} create deployment allowed --image="${CONTAINER_PATH}"

# This deployment is blocked; that the image doesn't exist is irrelevant, it is
# blocked by binauthz because there is no attestation for the given sha.
${k_prod} create deployment blocked --image="${REPO}/deny@sha256:dead1234567890beef1234567890cafe1234567890bad1234567890deed12345"

${k_prod} get deployments

${k_prod} get events | fgrep "${REPO}"
