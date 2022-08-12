#!/bin/sh
set -e

dir=$(dirname $0)
. "${dir}"/env.sh

pipelinerun=$(mktemp)
envsubst < "${dir}/pipelinerun.yaml" > "${pipelinerun}"
${k_tekton} create --filename "${pipelinerun}"
rm -rf "${pipelinerun}"

# Wait for completion!
${tkn} pr logs --last -f
