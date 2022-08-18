#!/bin/sh
# This script assumes that ./setup.sh has been run but that ~/.kube/config has
# not been setup up -- perhaps because setup was run on a different machine.
# Run this script to drop GKE credentials into place.
set -e

dir=$(dirname $0)
. "${dir}"/env.sh

# Set up kubectl credentials
${gcloud} container clusters \
    get-credentials --zone=${ZONE} "${TEKTON_CLUSTER}"
