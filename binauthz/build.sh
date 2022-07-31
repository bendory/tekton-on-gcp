#!/bin/sh
# This script will build container ${IMAGE} suitable for deployment in the
# ${PROD_CLUSTER} created by the setup.sh script in this directory.
set -e

dir=$(dirname $0)
. "${dir}"/../env.sh

${k_tekton} apply --filename "${dir}/task.yaml"

taskrun=$(mktemp)
cp "${dir}/taskrun.yaml" "${taskrun}"
echo "    value: ${LOCATION}-docker.pkg.dev/${PROJECT}/${REPO}/${IMAGE}" >> "${taskrun}"
${k_tekton} create --filename "${taskrun}"
rm -rf "${taskrun}"

# Wait for completion!
${tkn} tr logs --last -f
