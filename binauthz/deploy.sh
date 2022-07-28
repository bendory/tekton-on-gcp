#!/bin/sh
# This script will deploy ${IMAGE} to ${CLUSTER} and demonstrate binauth
# enforcement by attempting to deploy a blocked image.
set -e

dir=$(dirname $0)
. "${dir}"/env.sh

REPO="${LOCATION}-docker.pkg.dev/${PROJECT}/${REPO}"

# This deployment is allowed.
${kubectl} create deployment allowed --image="${REPO}/${IMAGE}"

# This deployment is blocked.
${kubectl} create deployment blocked --image="${REPO}/deny"

${kubectl} get deployments

${kubectl} get events | fgrep "${REPO}"
