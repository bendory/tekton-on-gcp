#!/bin/sh

dir=$(dirname $0)
. "${dir}"/../shared_env.sh

export CLUSTER=prod
export IMAGE=allow
export ATTESTOR_NAME=tekton-chains-attestor
export CONTEXT=gke_${PROJECT}_${REGION}_${CLUSTER} # context for kubectl

# Pre-requisites: installation of Cloud SDK, kubectl, tkn
gcloud=$(which gcloud)   || ( echo "gcloud not found" && exit 1 )
kubectl=$(which kubectl) || ( echo "kubectl not found" && exit 1 )
_=$(which kubectl-tkn)   || ( echo "tkn not found" && exit 1 )

gcloud="${gcloud} --project=${PROJECT}"
tkn="${kubectl} tkn --context=${CONTEXT}"
kubectl="${kubectl} --context=${CONTEXT}"
