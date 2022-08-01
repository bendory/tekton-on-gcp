#!/bin/sh
set -e

dir=$(dirname $0)
. "${dir}"/env.sh

# Start API enablements so we don't have to wait for them below.
${gcloud} services enable artifactregistry.googleapis.com --async    # AR
${gcloud} services enable cloudkms.googleapis.com --async            # KMS
${gcloud} services enable compute.googleapis.com --async             # GCE
${gcloud} services enable container.googleapis.com --async           # GKE
${gcloud} services enable containeranalysis.googleapis.com --async   # Container Analysis
${gcloud} services enable containerfilesystem.googleapis.com --async # Streaming images
${gcloud} services enable iam.googleapis.com --async                 # IAM

# Create the BUILDER_SA. The BUILDER_SA is the ServiceAccount identity that will
# be used to authenticate and authorize GCP calls during the build.
${gcloud} services enable iam.googleapis.com # Ensure IAM is enabled
${gcloud} iam service-accounts create "${BUILDER}" \
    --description="Tekton Build-time Service Account" \
    --display-name="Tekton Builder"

# Set up Artifact Registry: create a docker repository and authorize the
# BUILDER_SA to push images to it.
${gcloud} services enable artifactregistry.googleapis.com # Ensure AR is enabled
${gcloud} artifacts repositories create "${REPO}" \
    --repository-format=docker --location="${LOCATION}"
${gcloud} projects add-iam-policy-binding "${PROJECT}" \
    --member="serviceAccount:${BUILDER_SA}" --role='roles/artifactregistry.writer'

# Set up GKE with Workload Identity and Image Streaming
# Workload Identity is used to map a Kubernetes Service Account to our desired
# BUILDER_SA.
# https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity
# Image Streaming enables faster loading of containers.
# https://cloud.google.com/kubernetes-engine/docs/how-to/image-streaming
${gcloud} services enable \
    compute.googleapis.com \
    container.googleapis.com \
    containerfilesystem.googleapis.com # Ensure Image Streaming is enabled
${gcloud} container clusters create "${TEKTON_CLUSTER}" \
    --region="${REGION}" --workload-pool="${PROJECT}.svc.id.goog" \
    --image-type="COS_CONTAINERD" --enable-image-streaming
${gcloud} container node-pools update "${NODE_POOL}" \
    --region=${REGION} --cluster="${TEKTON_CLUSTER}" --workload-metadata=GKE_METADATA
${gcloud} container clusters \
    get-credentials --region=${REGION} "${TEKTON_CLUSTER}" # Set up kubectl credentials
${gcloud} iam service-accounts add-iam-policy-binding \
    "${BUILDER_SA}" --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:${PROJECT}.svc.id.goog[default/default]"

${k_tekton} annotate serviceaccount \
    --namespace default default iam.gke.io/gcp-service-account="${BUILDER_SA}"

# Install Tekton Pipelines CRDs.
${k_tekton} apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

# Wait for pipelines to be ready.
unset status
while [[ "${status}" -ne "Running" ]]; do
  echo "Waiting for Tekton Pipelines installation to complete."
  status=$(${k_tekton} get pods --namespace tekton-pipelines -o custom-columns=':status.phase' | sort -u)
done
echo "Tekton Pipelines installation completed."

# Install tasks
${tkn} hub install task git-clone
sleep 2 # No idea why a pause prevents flakes.
${tkn} hub install task kaniko

# Install Tekton Chains. Tekton Chains will gather build provenance for images
# and attest to their provenance from this Tekton installation.
# We need a chains release >=v0.11.0 to pick up a bugfix in the grafeas
# implementation; latest is currently at v0.9.0.
#${k_tekton} apply --filename https://storage.googleapis.com/tekton-releases/chains/latest/release.yaml
${k_tekton} apply --filename https://storage.googleapis.com/tekton-releases/chains/previous/v0.11.0/release.yaml

unset status
while [[ "${status}" -ne "Running" ]]; do
  echo "Waiting for Tekton Chains installation to complete."
  status=$(${k_tekton} get pods --namespace "${CHAINS_NS}" -o custom-columns=':status.phase' | sort -u)
done
echo "Tekton Chains installation completed."

# Configure Workload Identity for the Chains namespace. Chains runs in a
# different namespace and as a different Kubernetes Service Account in order to
# separate responsibilities between pipelines and Chains.
${gcloud} iam service-accounts create "${VERIFIER}" \
    --description="Tekton Chains Service Account" \
    --display-name="Tekton Chains"
${gcloud} iam service-accounts add-iam-policy-binding \
    $VERIFIER_SA --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:$PROJECT.svc.id.goog[${CHAINS_NS}/${VERIFIER}]"
${k_tekton} annotate serviceaccount "${VERIFIER}" --namespace "${CHAINS_NS}" \
    iam.gke.io/gcp-service-account=${VERIFIER_SA}

# Configure Key Management Service. Set up a private key that will be used by
# VERIFIER_SA to sign attestations.
${gcloud} services enable cloudkms.googleapis.com # Ensure KMS is available.
${gcloud} kms keyrings create "${KEYRING}" --location "${LOCATION}"
${gcloud} kms keys create "${KEY}" \
    --keyring "${KEYRING}" \
    --location "${LOCATION}" \
    --purpose "asymmetric-signing" \
    --default-algorithm "rsa-sign-pkcs1-2048-sha256"
${gcloud} kms keys add-iam-policy-binding "${KEY}" \
    --location="${LOCATION}" --keyring="${keyring}" \
    --member "serviceAccount:${VERIFIER_SA}" --role "roles/cloudkms.cryptoOperator"
${gcloud} projects add-iam-policy-binding "${PROJECT}" \
    --member "serviceAccount:${VERIFIER_SA}" --role "roles/cloudkms.viewer"

# Configure Tekton Chains to use simplesigning with a KMS key and store the OCI
# in grafeas (Container Analysis); TaskRuns will be captured using in-toto
# format, signed with a KMS key and stored in grafeas.
${k_tekton} patch configmap chains-config -n "${CHAINS_NS}" \
    -p='{"data":{
    "artifacts.oci.format":      "simplesigning",
    "artifacts.oci.signer":      "kms",
    "artifacts.oci.storage":     "grafeas",
    "artifacts.taskrun.format":  "in-toto",
    "artifacts.taskrun.signer":  "kms",
    "artifacts.taskrun.storage": "grafeas" }}'

# Configure the KMS signing key, storage project in Container Analysis, and
# builder identifier used by Tekton Chains.
export KMS_REF=gcpkms://projects/${PROJECT}/locations/${LOCATION}/keyRings/${KEYRING}/cryptoKeys/${KEY}
${k_tekton} patch configmap chains-config -n "${CHAINS_NS}" \
    -p="{\"data\": {\
    \"signers.kms.kmsref\":        \"${KMS_REF}\", \
    \"storage.grafeas.projectid\": \"${PROJECT}\", \
    \"builder.id\":                \"${CONTEXT}\" }}"

# Enable the VERIFIER_SA to write Notes and Occurrences in Container Analysis.
${gcloud} services enable containeranalysis.googleapis.com # Ensure Container Analysis is enabled.
${gcloud} projects add-iam-policy-binding "${PROJECT}" \
    --role roles/containeranalysis.notes.editor \
    --member "serviceAccount:${VERIFIER_SA}"
${gcloud} projects add-iam-policy-binding "${PROJECT}" \
    --role roles/containeranalysis.occurrences.editor \
    --member "serviceAccount:${VERIFIER_SA}"

# Apply pipeline.yaml; see https://tekton.dev/docs/how-to-guides/kaniko-build-push/
${k_tekton} apply --filename "${dir}/pipeline.yaml"

echo "Setup complete! Run ./run_pipeline.sh to build and push your first container."
