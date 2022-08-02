#!/bin/sh
set -e

dir=$(dirname $0)
. "${dir}"/../env.sh

# These APIs should all have been enabled during Tekton installation, so this
# should be a no-op.
${gcloud} services enable artifactregistry.googleapis.com \
    binaryauthorization.googleapis.com \
    cloudkms.googleapis.com \
    compute.googleapis.com \
    container.googleapis.com \
    containeranalysis.googleapis.com \
    containerfilesystem.googleapis.com \
    iam.googleapis.com

# Allow default GKE service account to pull images from AR for deployment.
PROJECT_NUMBER=$(${gcloud} projects describe $PROJECT --format='value(projectNumber)')
${gcloud} projects add-iam-policy-binding $PROJECT \
    --role=roles/artifactregistry.reader \
    --member=serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com

# Set up the attestor
# https://codelabs.developers.google.com/codelabs/cloud-binauthz-intro/index.html#5
# The note name "tekton-default-simplesigning" comes from Tekton Chains.
NOTE_ID=projects/${PROJECT}/notes/tekton-default-simplesigning
# Allow ATTESTOR_SA to read notes.
ATTESTOR_SA=service-${PROJECT_NUMBER}@gcp-sa-binaryauthorization.iam.gserviceaccount.com
${gcloud} projects add-iam-policy-binding $PROJECT \
    --member="serviceAccount:${ATTESTOR_SA}" \
    --role=roles/containeranalysis.notes.occurrences.viewer

# Create the attestor; note that the attestor must be set up before the binauthz
# policy referencing it is applied.
${gcloud} container binauthz attestors create "${ATTESTOR_NAME}" \
    --attestation-authority-note="${NOTE_ID}" \
    --attestation-authority-note-project="${PROJECT}"

# Add the key to the attestor
${gcloud} container binauthz attestors public-keys add \
    --attestor="${ATTESTOR_NAME}" \
    --keyversion-project="${PROJECT}" \
    --keyversion-location="${LOCATION}" \
    --keyversion-keyring="${KEYRING}" \
    --keyversion-key="${KEY}" \
    --keyversion="1"

# Set up binauth policy
policydir=$(mktemp -d)
policy="${policydir}/policy.yaml"
cp "${dir}/policy.yaml" "${policy}"
echo "      projects/${PROJECT}/attestors/${ATTESTOR_NAME}" >> "${policy}"
${gcloud} container binauthz policy import "${policy}"
rm -rf "${policydir}"

# Create cluster with binauthz enabled.
${gcloud} container clusters create \
    --binauthz-evaluation-mode=PROJECT_SINGLETON_POLICY_ENFORCE \
    --image-type="COS_CONTAINERD" --enable-image-streaming \
    --num-nodes=1 --region="${REGION}" --machine-type="e2-micro" "${PROD_CLUSTER}"

