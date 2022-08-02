#!/bin/sh
# This script will deploy ${IMAGE} to ${PROD_CLUSTER} and demonstrate binauth
# enforcement by attempting to deploy a blocked image.
set -e

dir=$(dirname $0)
. "${dir}"/../env.sh

BASE="${LOCATION}-docker.pkg.dev/${PROJECT}/${REPO}"

# Resolve :latest to a specific digest.
CONTAINER_PATH=$(${gcloud} artifacts docker images describe ${BASE}/${IMAGE}:latest --format='value(image_summary.fully_qualified_digest)')

# This deployment is allowed.
${k_prod} create deployment allowed --image="${CONTAINER_PATH}"

# This deployment is blocked; that the image doesn't exist is irrelevant, it is
# blocked by binauthz because there is no attestation for the given sha.
${k_prod} create deployment blocked --image="${BASE}/deny@sha256:dead1234567890beef1234567890cafe1234567890bad1234567890deed12345"

${k_prod} get deployments

${k_prod} get events | fgrep "${REPO}"
