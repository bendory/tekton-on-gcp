#!/bin/sh
set -e

dir=$(dirname $0)
. "${dir}"/env.sh

pipelinerun=$(mktemp)
cp pipelinerun.yaml "${pipelinerun}"
echo "    value: ${LOCATION}-docker.pkg.dev/${PROJECT}/${REPO}/mini-true" >> "${pipelinerun}"
${kubectl} create --filename "${pipelinerun}"
rm -rf "${pipelinerun}"

# Wait for completion!
${tkn} pr logs --last -f
