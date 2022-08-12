#!/bin/sh
set -e

dir=$(dirname $0)
. "${dir}"/env.sh

# Start API enablements so we don't have to wait for them below.
# For reasons I don't know, running artifactregistry enablement --async here and
# blocking on it below just before repository creation often leads to an error
# indicating that the API is not yet enabled. I am guessing there is a
# propogation issue. Workaround: synchronously enable here.
${gcloud} services enable artifactregistry.googleapis.com
${gcloud} services enable binaryauthorization.googleapis.com --async # Binary Authorization
${gcloud} services enable cloudkms.googleapis.com --async            # KMS
${gcloud} services enable compute.googleapis.com --async             # GCE
${gcloud} services enable container.googleapis.com --async           # GKE
${gcloud} services enable containeranalysis.googleapis.com --async   # Container Analysis
${gcloud} services enable containerfilesystem.googleapis.com --async # Streaming Images
${gcloud} services enable iam.googleapis.com --async                 # IAM

# Create the BUILDER_SA. The BUILDER_SA is the ServiceAccount identity that will
# be used to authenticate and authorize GCP calls during the build.
${gcloud} services enable iam.googleapis.com # Ensure IAM is enabled
${gcloud} iam service-accounts create "${BUILDER}" \
    --description="Tekton Build-time Service Account" \
    --display-name="Tekton Builder"

# Set up Artifact Registry: create a docker repository and authorize the
# BUILDER_SA to push images to it.
${gcloud} artifacts repositories create "${REPO}" \
    --repository-format=docker --location="${LOCATION}"
${gcloud} projects add-iam-policy-binding "${PROJECT}" \
    --member="serviceAccount:${BUILDER_SA}" --role='roles/artifactregistry.writer'

# Set up VERIFIER_SA.
${gcloud} iam service-accounts create "${VERIFIER}" \
    --description="Tekton Chains Service Account" \
    --display-name="Tekton Chains"

# Enable the VERIFIER_SA to write Notes and Occurrences in Container Analysis.
${gcloud} services enable containeranalysis.googleapis.com # Ensure Container Analysis is enabled.
${gcloud} projects add-iam-policy-binding "${PROJECT}" \
    --role roles/containeranalysis.notes.editor \
    --member "serviceAccount:${VERIFIER_SA}"
${gcloud} projects add-iam-policy-binding "${PROJECT}" \
    --role roles/containeranalysis.occurrences.editor \
    --member "serviceAccount:${VERIFIER_SA}"

# Configure Key Management Service. Set up a private key that will be used by
# VERIFIER_SA to sign attestations.
# NOTE: the below commands assume that key_setup.sh in this directory has
# already executed successfully.
${key_gcloud} services enable cloudkms.googleapis.com # Ensure KMS is available.
if ${key_gcloud} kms keyrings describe "${KEYRING}" --location "${LOCATION}"; then
  echo "KEYRING ${KEYRING} found."
else
  echo "KEYRING ${KEYRING} NOT found. That's OK, I'll create it now."
  ${key_gcloud} kms keyrings create "${KEYRING}" --location "${LOCATION}"
  echo "KEYRING ${KEYRING} created successfully."
fi
${key_gcloud} kms keys create "${KEY}" \
    --keyring "${KEYRING}" \
    --location "${LOCATION}" \
    --purpose "asymmetric-signing" \
    --default-algorithm "rsa-sign-pkcs1-2048-sha256"
${key_gcloud} kms keys add-iam-policy-binding "${KEY}" \
    --location="${LOCATION}" --keyring="${KEYRING}" \
    --member "serviceAccount:${VERIFIER_SA}" --role "roles/cloudkms.cryptoOperator"
${key_gcloud} kms keys add-iam-policy-binding "${KEY}" \
    --location="${LOCATION}" --keyring="${KEYRING}" \
    --member "serviceAccount:${VERIFIER_SA}" --role "roles/cloudkms.viewer"

# Set up GKE with Workload Identity, Binary Authorization, and Image Streaming
# Workload Identity is used to map a Kubernetes Service Account to our desired
# BUILDER_SA.
# https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity
# Image Streaming enables faster loading of containers.
# https://cloud.google.com/kubernetes-engine/docs/how-to/image-streaming
${gcloud} services enable \
    binaryauthorization.googleapis.com \
    compute.googleapis.com \
    container.googleapis.com \
    containerfilesystem.googleapis.com
${gcloud} container clusters create "${TEKTON_CLUSTER}" \
    --zone="${ZONE}" --workload-pool="${PROJECT}.svc.id.goog" \
    --num-nodes=1 --image-type="COS_CONTAINERD" --enable-image-streaming \
    --binauthz-evaluation-mode="PROJECT_SINGLETON_POLICY_ENFORCE" \
    --enable-autoscaling --min-nodes=1 --max-nodes=5 \
    --workload-metadata="GKE_METADATA"
${gcloud} container clusters \
    get-credentials --zone=${ZONE} "${TEKTON_CLUSTER}" # Set up kubectl credentials
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
# Latest version 0.8 has a bug that causes failure in our pipelines. :-(
${tkn} hub install task git-clone --version=0.7
sleep 10 # No idea why a pause reduces flakes.
${tkn} hub install task kaniko || ${tkn} hub install task kaniko

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
${gcloud} iam service-accounts add-iam-policy-binding \
    $VERIFIER_SA --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:$PROJECT.svc.id.goog[${CHAINS_NS}/${VERIFIER}]"
${k_tekton} annotate serviceaccount "${VERIFIER}" --namespace "${CHAINS_NS}" \
    iam.gke.io/gcp-service-account=${VERIFIER_SA}

# Configure Tekton Chains to use simplesigning of images; TaskRuns will be
# captured using in-toto. Attestations for both will be signed with a KMS key
# and stored in *BOTH* grafeas (Container Analysis) and in OCI bundles alongside
# the image itself in Artifact Registry.
# NOTE: by not setting `storage.oci.repository`, we store the OCI alongside the
# image itself in the image registry.
${k_tekton} patch configmap chains-config -n "${CHAINS_NS}" \
    -p='{"data":{
    "artifacts.oci.format":      "simplesigning",
    "artifacts.oci.signer":      "kms",
    "artifacts.oci.storage":     "grafeas,oci",
    "artifacts.taskrun.format":  "in-toto",
    "artifacts.taskrun.signer":  "kms",
    "artifacts.taskrun.storage": "grafeas,oci" }}'

# Configure the KMS signing key, storage project in Container Analysis, and
# builder identifier used by Tekton Chains.
${k_tekton} patch configmap chains-config -n "${CHAINS_NS}" \
    -p="{\"data\": {\
    \"signers.kms.kmsref\":        \"${KMS_URI}\", \
    \"storage.grafeas.projectid\": \"${PROJECT}\", \
    \"builder.id\":                \"${CONTEXT}\" }}"

# To store OCI attestations alongside the image in AR, VERIFIER_SA needs
# write permission.
${gcloud} projects add-iam-policy-binding "${PROJECT}" \
    --member="serviceAccount:${VERIFIER_SA}" --role='roles/artifactregistry.writer'

# Apply pipeline.yaml; see https://tekton.dev/docs/how-to-guides/kaniko-build-push/
${k_tekton} apply --filename "${dir}/pipeline.yaml"

echo "Setup complete! Run ./run_pipeline.sh to build and push your first container."
