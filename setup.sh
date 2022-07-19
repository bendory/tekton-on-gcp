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
export BUILDER_SA="${BUILDER}@${PROJECT}.iam.gserviceaccount.com"
export CHAINS_NS=tekton-chains
export VERIFIER=tekton-chains
export VERIFIER_SA="${VERIFIER}@${PROJECT}.iam.gserviceaccount.com"
export KEY=tekton-signing-key
export KEYRING=tekton-keyring

gcloud config configurations create "tekton-setup"
gcloud config set core/account "${ACCOUNT}"
gcloud config set core/project "${PROJECT}"

# Start API enablements so we don't have to wait for them below.
gcloud services enable artifactregistry.googleapis.com --async  # AR
gcloud services enable cloudkms.googleapis.com --async          # KMS
gcloud services enable compute.googleapis.com --async           # GCE
gcloud services enable container.googleapis.com --async         # GKE
gcloud services enable containeranalysis.googleapis.com --async # Container Analysis
gcloud services enable iam.googleapis.com --async               # IAM

# Can't set properties until APIs are enabled!
gcloud services enable compute.googleapis.com # Ensure GCE is enabled
gcloud config set compute/region "${REGION}"

# Let all Googlers view this project
gcloud services enable iam.googleapis.com # Ensure IAM is enabled
gcloud projects add-iam-policy-binding "${PROJECT}" --member='domain:google.com' --role='roles/viewer'

# Create the BUILDER_SA
gcloud iam service-accounts create "${BUILDER}"

# Set up AR
gcloud services enable artifactregistry.googleapis.com # Ensure AR is enabled
gcloud artifacts repositories create "${REPO}" --repository-format=docker --location="${LOCATION}"
gcloud projects add-iam-policy-binding "${PROJECT}" \
    --member="serviceAccount:${BUILDER_SA}" --role='roles/artifactregistry.writer'

# Set up GKE with Workload Identity
# https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity
gcloud services enable container.googleapis.com # Ensure GKE is enabled
gcloud config set container/cluster "${CLUSTER}"
gcloud container clusters create "${CLUSTER}" --region="${REGION}" --workload-pool="${PROJECT}.svc.id.goog"
gcloud container node-pools update "${NODE_POOL}" --cluster="${CLUSTER}" --workload-metadata=GKE_METADATA
gcloud container clusters get-credentials "${CLUSTER}" # Set up kubectl credentials
gcloud iam service-accounts add-iam-policy-binding "${BUILDER_SA}" \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:${PROJECT}.svc.id.goog[default/default]"

kubectl annotate serviceaccount --namespace default default iam.gke.io/gcp-service-account="${BUILDER_SA}"

# Install Tekton
kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
tkn hub install task git-clone
tkn hub install task kaniko

# Wait for pipelines to be ready.
unset status
while [[ "${status}" -ne "Running" ]]; do
  echo "Waiting for Tekton Pipelines installation to complete."
  status=$(kubectl get pods --namespace tekton-pipelines -o custom-columns=':status.phase' | sort -u)
done
echo "Tekton Pipelines installation completed."

# Install Chains
kubectl apply --filename https://storage.googleapis.com/tekton-releases/chains/latest/release.yaml
unset status
while [[ "${status}" -ne "Running" ]]; do
  echo "Waiting for Tekton Chains installation to complete."
  status=$(kubectl get pods --namespace "${CHAINS_NS}" -o custom-columns=':status.phase' | sort -u)
done
echo "Tekton Chains installation completed."

# Configure Chains
gcloud iam service-accounts create "${VERIFIER}"
gcloud iam service-accounts add-iam-policy-binding "${VERIFIER_SA}" \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:${PROJECT}.svc.id.goog[${CHAINS_NS}/default]"
kubectl annotate serviceaccount --namespace "${CHAINS_NS}" default iam.gke.io/gcp-service-account="${VERIFIER_SA}"

# Configure KMS
gcloud services enable cloudkms.googleapis.com # Ensure KMS is available.
gcloud kms keyrings create "${KEYRING}" --location "${LOCATION}"
gcloud kms keys create "${KEY}" \
    --keyring "${KEYRING}" \
    --location "${LOCATION}" \
    --purpose "asymmetric-signing" \
    --default-algorithm "rsa-sign-pkcs1-2048-sha256"
# TODO: narrow this, restrict to just the needed key.
gcloud projects add-iam-policy-binding "${PROJECT}" \
    --member "serviceAccount:${VERIFIER_SA}" --role "roles/cloudkms.cryptoOperator"
gcloud projects add-iam-policy-binding "${PROJECT}" \
    --member "serviceAccount:${VERIFIER_SA}" --role "roles/cloudkms.viewer"
gcloud kms keys add-iam-policy-binding "${KEY}" \
    --keyring="${KEYRING}" --location="${LOCATION}" \
    --member="serviceAccount:${VERIFIER_SA}" --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"
gcloud kms keys add-iam-policy-binding "${KEY}" \
    --keyring="${KEYRING}" --location="${LOCATION}" \
    --member="domain:google.com" --role="roles/cloudkms.verifier"

# Configure signatures
kubectl patch configmap chains-config -n tekton-chains -p='{"data":{
    "artifacts.oci.format": "simplesigning",
    "artifacts.oci.signer": "kms",
    "artifacts.oci.storage": "grafeas",
    "artifacts.taskrun.format": "in-toto",
    "artifacts.taskrun.signer": "kms",
    "artifacts.taskrun.storage": "grafeas" }}'

export KMS_REF=gcpkms://projects/${PROJECT}/locations/${LOCATION}/keyRings/${KEYRING}/cryptoKeys/${KEY}
kubectl patch configmap chains-config -n tekton-chains -p="{\"data\": {\"signers.kms.kmsref\": \"${KMS_REF}\"}}"
kubectl patch configmap chains-config -n tekton-chains -p="{\"data\": {\"storage.grafeas.projectid\": \"${PROJECT}\"}}"

# Grant tekton-chains-controller access to VERIFIER_SA
gcloud iam service-accounts add-iam-policy-binding $VERIFIER_SA \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:$PROJECT.svc.id.goog[${CHAINS_NS}/tekton-chains-controller]"
kubectl annotate serviceaccount tekton-chains-controller \
    --namespace "${CHAINS_NS}" \
    iam.gke.io/gcp-service-account=${VERIFIER_SA}

# Configure Container Analysis
gcloud services enable containeranalysis.googleapis.com # Ensure Container Analysis is enabled.
gcloud projects add-iam-policy-binding "${PROJECT}" \
    --role roles/containeranalysis.notes.editor \
    --member "serviceAccount:${VERIFIER_SA}"
gcloud projects add-iam-policy-binding "${PROJECT}" \
    --role roles/containeranalysis.occurrences.editor \
    --member "serviceAccount:${VERIFIER_SA}"

# Apply pipeline.yaml; see https://tekton.dev/docs/how-to-guides/kaniko-build-push/
kubectl apply --filename pipeline.yaml
echo "    value: us-docker.pkg.dev/${PROJECT}/${REPO}/mini-true" >> pipelinerun.yaml
kubectl create --filename pipelinerun.yaml

# Wait for completion!
tkn pr logs -f
