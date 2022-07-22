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
export VERIFIER=tekton-chains-controller
export VERIFIER_SA="${VERIFIER}@${PROJECT}.iam.gserviceaccount.com"
export KEY=tekton-signing-key
export KEYRING=tekton-keyring

# Start API enablements so we don't have to wait for them below.
gcloud --project=${PROJECT} services enable artifactregistry.googleapis.com --async  # AR
gcloud --project=${PROJECT} services enable cloudkms.googleapis.com --async          # KMS
gcloud --project=${PROJECT} services enable compute.googleapis.com --async           # GCE
gcloud --project=${PROJECT} services enable container.googleapis.com --async         # GKE
gcloud --project=${PROJECT} services enable containeranalysis.googleapis.com --async # Container Analysis
gcloud --project=${PROJECT} services enable iam.googleapis.com --async               # IAM

# Can't set properties until APIs are enabled!
gcloud --project=${PROJECT} services enable compute.googleapis.com # Ensure GCE is enabled

# Let all Googlers view this project
gcloud --project=${PROJECT} services enable iam.googleapis.com # Ensure IAM is enabled
gcloud projects add-iam-policy-binding "${PROJECT}" --member='domain:google.com' --role='roles/viewer'

# Create the BUILDER_SA
gcloud --project=${PROJECT} iam service-accounts create "${BUILDER}" \
    --description="Tekton Build-time Service Account" \
    --display-name="Tekton Builder"

# Set up AR
gcloud --project=${PROJECT} services enable artifactregistry.googleapis.com # Ensure AR is enabled
gcloud --project=${PROJECT} artifacts repositories create "${REPO}" \
    --repository-format=docker --location="${LOCATION}"
gcloud projects add-iam-policy-binding "${PROJECT}" \
    --member="serviceAccount:${BUILDER_SA}" --role='roles/artifactregistry.writer'

# Set up GKE with Workload Identity
# https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity
gcloud --project=${PROJECT} services enable container.googleapis.com # Ensure GKE is enabled
gcloud --project=${PROJECT} container clusters create "${CLUSTER}" \
    --region="${REGION}" --workload-pool="${PROJECT}.svc.id.goog"
gcloud --project=${PROJECT} container node-pools update "${NODE_POOL}" \
    --region=${REGION} --cluster="${CLUSTER}" --workload-metadata=GKE_METADATA
gcloud --project=${PROJECT} container clusters \
    get-credentials --region=${REGION} "${CLUSTER}" # Set up kubectl credentials
gcloud --project=${PROJECT} iam service-accounts add-iam-policy-binding \
    "${BUILDER_SA}" --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:${PROJECT}.svc.id.goog[default/default]"

kubectl annotate serviceaccount --namespace default default iam.gke.io/gcp-service-account="${BUILDER_SA}"

# Install Tekton
kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

# Wait for pipelines to be ready.
unset status
while [[ "${status}" -ne "Running" ]]; do
  echo "Waiting for Tekton Pipelines installation to complete."
  status=$(kubectl get pods --namespace tekton-pipelines -o custom-columns=':status.phase' | sort -u)
done
echo "Tekton Pipelines installation completed."

# Install tasks
tkn hub install task git-clone
tkn hub install task kaniko

# Install Chains
#kubectl apply --filename https://storage.googleapis.com/tekton-releases/chains/latest/release.yaml
#
# For now, we kluge chains installation from HEAD, we need a chains release
# >v0.9.0 to pick up a change in the grafeas implementation; v0.9.0 doesn't
# write the NOTE to the current resourceURI.
export PROJECT_NUM=$(gcloud projects describe "${PROJECT}" --format "value(projectNumber)")
gcloud projects add-iam-policy-binding "${PROJECT}" \
    --member="serviceAccount:${PROJECT_NUM}-compute@developer.gserviceaccount.com" \
    --role='roles/artifactregistry.reader'

HERE=$(pwd)
TMP=$(mktemp -d)
cd ${TMP}
git clone --depth=1 https://github.com/tektoncd/chains.git
cd chains
export KO_DOCKER_REPO=${LOCATION}-docker.pkg.dev/${PROJECT}/${REPO}
ko apply -f config/
cd ${HERE}
rm -rf ${TMP}
# END OF CHAINS KLUGE

unset status
while [[ "${status}" -ne "Running" ]]; do
  echo "Waiting for Tekton Chains installation to complete."
  status=$(kubectl get pods --namespace "${CHAINS_NS}" -o custom-columns=':status.phase' | sort -u)
done
echo "Tekton Chains installation completed."

# Configure Chains KSA / GSA
gcloud --project=${PROJECT} iam service-accounts create "${VERIFIER}" \
    --description="Tekton Chains Service Account" \
    --display-name="Tekton Chains"
gcloud --project=${PROJECT} iam service-accounts add-iam-policy-binding \
    $VERIFIER_SA --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:$PROJECT.svc.id.goog[${CHAINS_NS}/${VERIFIER}]"
kubectl annotate serviceaccount "${VERIFIER}" --namespace "${CHAINS_NS}" \
    iam.gke.io/gcp-service-account=${VERIFIER_SA}

# Configure KMS
gcloud --project=${PROJECT} services enable cloudkms.googleapis.com # Ensure KMS is available.
gcloud --project=${PROJECT} kms keyrings create "${KEYRING}" --location "${LOCATION}"
gcloud --project=${PROJECT} kms keys create "${KEY}" \
    --keyring "${KEYRING}" \
    --location "${LOCATION}" \
    --purpose "asymmetric-signing" \
    --default-algorithm "rsa-sign-pkcs1-2048-sha256"
gcloud projects add-iam-policy-binding "${PROJECT}" \
    --member "serviceAccount:${VERIFIER_SA}" --role "roles/cloudkms.cryptoOperator"
gcloud projects add-iam-policy-binding "${PROJECT}" \
    --member "serviceAccount:${VERIFIER_SA}" --role "roles/cloudkms.viewer"
gcloud --project=${PROJECT} kms keys add-iam-policy-binding "${KEY}" \
    --keyring="${KEYRING}" --location="${LOCATION}" \
    --member="serviceAccount:${VERIFIER_SA}" --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"
gcloud --project=${PROJECT} kms keys add-iam-policy-binding "${KEY}" \
    --keyring="${KEYRING}" --location="${LOCATION}" \
    --member="domain:google.com" --role="roles/cloudkms.verifier"

# Configure signatures
kubectl patch configmap chains-config -n "${CHAINS_NS}" -p='{"data":{
    "artifacts.oci.format":      "simplesigning",
    "artifacts.oci.signer":      "kms",
    "artifacts.oci.storage":     "grafeas",
    "artifacts.taskrun.format":  "in-toto",
    "artifacts.taskrun.signer":  "kms",
    "artifacts.taskrun.storage": "grafeas" }}'

export KMS_REF=gcpkms://projects/${PROJECT}/locations/${LOCATION}/keyRings/${KEYRING}/cryptoKeys/${KEY}
kubectl patch configmap chains-config -n "${CHAINS_NS}" -p="{\"data\": {\
    \"signers.kms.kmsref\":        \"${KMS_REF}\", \
    \"storage.grafeas.projectid\": \"${PROJECT}\", \
    \"builder.id\":                \"$(kubectl config current-context)\" }}"

# Configure Container Analysis
gcloud --project=${PROJECT} services enable containeranalysis.googleapis.com # Ensure Container Analysis is enabled.
gcloud projects add-iam-policy-binding "${PROJECT}" \
    --role roles/containeranalysis.notes.editor \
    --member "serviceAccount:${VERIFIER_SA}"
gcloud projects add-iam-policy-binding "${PROJECT}" \
    --role roles/containeranalysis.occurrences.editor \
    --member "serviceAccount:${VERIFIER_SA}"

# Apply pipeline.yaml; see https://tekton.dev/docs/how-to-guides/kaniko-build-push/
kubectl apply --filename pipeline.yaml

echo "Setup complete! Run ./run_pipeline.sh to build and push your first container."
