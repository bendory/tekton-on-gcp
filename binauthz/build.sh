#!/bin/sh
# This script will build container ${IMAGE} suitable for deployment in the
# ${CLUSTER} created by the setup.sh script in this directory.
set -e

dir=$(dirname $0)/..
. "${dir}"/env.sh
dir=$(dirname $0)

${kubectl} apply --filename "${dir}/pipeline.yaml"

pipelinerun=$(mktemp)
cp "${dir}/pipelinerun.yaml" "${pipelinerun}"
echo "    value: ${LOCATION}-docker.pkg.dev/${PROJECT}/${REPO}/${IMAGE}" >> "${pipelinerun}"
${kubectl} create --filename "${pipelinerun}"
rm -rf "${pipelinerun}"

# Wait for completion!
${tkn} pr logs --last -f
