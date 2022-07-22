#!/bin/sh
set -e

# Pre-requisites: installation of Cloud SDK, kubectl, tkn
# Pre-requisite: PROJECT is defined
# Pre-requisite: ${PROJECT} exists in GCP with billing enabled.
if [[ -z "${PROJECT}" ]]; then
  echo "Set envvar PROJECT to your GCP project before running this script."
  exit 1
fi;

export CLUSTER=tekton-showcase
export REGION=us-central1
export REPO=tekton
export LOCATION=us
export CONTEXT=gke_${PROJECT}_${REGION}_${CLUSTER} # context for kubectl

pipelinerun=$(mktemp)
cp pipelinerun.yaml "${pipelinerun}"
echo "    value: ${LOCATION}-docker.pkg.dev/${PROJECT}/${REPO}/mini-true" >> "${pipelinerun}"
kubectl --context=${CONTEXT} create --filename "${pipelinerun}"

# Wait for completion!
kubectl tkn --context=${CONTEXT} pr logs --last -f
