#!/bin/sh
# This script will build a container named 'allow' suitable for deployment in
# the "production" cluster created by the setup.sh script in this directory.
set -e

dir=$(dirname $0)
. "${dir}"/../env.sh

${kubectl} apply --filename "${dir}/pipeline.yaml"

pipelinerun=$(mktemp)
cp "${dir}/pipelinerun.yaml" "${pipelinerun}"
echo "    value: ${LOCATION}-docker.pkg.dev/${PROJECT}/${REPO}/allow" >> "${pipelinerun}"
${kubectl} create --filename "${pipelinerun}"
rm -rf "${pipelinerun}"

# Wait for completion!
${tkn} pr logs --last -f
