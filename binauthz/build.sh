#!/bin/sh
# This script will build container ${IMAGE} suitable for deployment in the
# ${PROD_CLUSTER} created by the setup.sh script in this directory.
set -e

dir=$(dirname $0)
. "${dir}"/../env.sh

${k_tekton} apply --filename "${dir}/task.yaml"

taskrun=$(mktemp)
envsubst < "${dir}/taskrun.yaml" > "${taskrun}"
${k_tekton} create --filename "${taskrun}"
rm -rf "${taskrun}"

# Wait for completion!
${tkn} tr logs --last -f
