#!/bin/sh
set -e

# Pre-requisites: installation of Cloud SDK, kubectl, tkn
# Pre-requisite: PROJECT is defined
# Pre-requisite: ${PROJECT} exists in GCP with billing enabled.
if [[ -z "${PROJECT}" ]]; then
  echo "Set envvar PROJECT to your GCP project before running this script."
  exit 1
fi;

# Pre-requisite: authentication for Cloud SDK
ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
if [[ -z "${ACCOUNT}" ]]; then
  echo "Run 'gcloud auth login' to authenticate on GCP before running this script."
  exit 1
fi;

export CLUSTER=tekton-showcase
export NODE_POOL=default-pool
export REGION=us-central1
export REPO=tekton
export LOCATION=us
export BUILDER=builder
export SA="${BUILDER}@${PROJECT}.iam.gserviceaccount.com"

gcloud config configurations create "tekton-setup"
gcloud config set core/account "${ACCOUNT}"
gcloud config set core/project "${PROJECT}"

# Start API enablements so we don't have to wait for them below.
gcloud services enable compute.googleapis.com --async          # GCE
gcloud services enable artifactregistry.googleapis.com --async # AR
gcloud services enable container.googleapis.com --async        # GKE
gcloud services enable iam.googleapis.com --async              # IAM

# Can't set properties until APIs are enabled!
gcloud services enable compute.googleapis.com # Ensure GCE is enabled
gcloud config set compute/region "${REGION}"

# Let all Googlers view this project
gcloud services enable iam.googleapis.com # Ensure IAM is enabled
gcloud projects add-iam-policy-binding "${PROJECT}" --member='domain:google.com' --role='roles/viewer'

# Create the builder SA
gcloud iam service-accounts create "${BUILDER}"

# Set up AR
gcloud services enable artifactregistry.googleapis.com # Ensure AR is enabled
gcloud artifacts repositories create "${REPO}" --repository-format=docker --location="${LOCATION}"
gcloud projects add-iam-policy-binding "${PROJECT}" --member="serviceAccount:${SA}" --role='roles/artifactregistry.writer'

# Set up GKE with Workload Identity
# https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity
gcloud services enable container.googleapis.com # Ensure GKE is enabled
gcloud config set container/cluster "${CLUSTER}"
gcloud container clusters create "${CLUSTER}" --region="${REGION}" --workload-pool="${PROJECT}.svc.id.goog"
gcloud container node-pools update "${NODE_POOL}" --cluster="${CLUSTER}" --workload-metadata=GKE_METADATA
gcloud iam service-accounts add-iam-policy-binding "${SA}" \
	--role roles/iam.workloadIdentityUser \
	--member "serviceAccount:${PROJECT}.svc.id.goog[default/default]"

gcloud container clusters get-credentials "${CLUSTER}" # Set up kubectl credentials
kubectl annotate serviceaccount --namespace default default iam.gke.io/gcp-service-account="${SA}"

# Install Tekton
kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml --wait=true
tkn hub install task git-clone
tkn hub install task kaniko
sleep 60 # TODO: How do I know when pipeline CRD is ready for use?
kubectl apply --filename pipeline.yaml

# Set up and apply pipelinerun.yaml, which is missing the target image name.
echo "    value: us-docker.pkg.dev/${PROJECT}/${REPO}/mini-true" >> pipelinerun.yaml
kubectl apply --filename pipelinerun.yaml

# Wait for completion!
tkn pr logs -f
