#!/bin/sh
set -e

# Pre-requisites: installation of Cloud SDK, kubectl, tkn
# Pre-requisite: PROJECT is defined
# Pre-requisite: ${PROJECT} exists in GCP with billing enabled.
if [[ -z "${PROJECT}" ]]; then
  echo "Set envvar PROJECT to your GCP project before running this script."
  exit 1
fi;

REPO=tekton
LOCATION=us

pipelinerun=$(mktemp)
cp pipelinerun.yaml "${pipelinerun}"
echo "    value: ${LOCATION}-docker.pkg.dev/${PROJECT}/${REPO}/mini-true" >> "${pipelinerun}"
kubectl create --filename "${pipelinerun}"

# Wait for completion!
tkn pr logs --last -f
