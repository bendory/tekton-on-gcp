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
# Create the attestor; note that the attestor must be set up before the binauthz
# policy referencing it is applied.
# https://cloud.google.com/binary-authorization/docs/creating-attestors-cli
NOTE_ID=projects/${PROJECT}/notes/tekton-default-simplesigning
${gcloud} container binauthz attestors create "${ATTESTOR_NAME}" \
    --attestation-authority-note="${NOTE_ID}" \
    --attestation-authority-note-project="${PROJECT}"

# Ordering counts! Note that the ATTESTOR_SA is only created after the attestor
# itself is created.
# https://codelabs.developers.google.com/codelabs/cloud-binauthz-intro/index.html#5
# The note name "tekton-default-simplesigning" comes from Tekton Chains.
# Allow ATTESTOR_SA to read notes.
ATTESTOR_SA=service-${PROJECT_NUMBER}@gcp-sa-binaryauthorization.iam.gserviceaccount.com
${gcloud} projects add-iam-policy-binding $PROJECT \
    --member="serviceAccount:${ATTESTOR_SA}" \
    --role=roles/containeranalysis.notes.occurrences.viewer

# Add the key to the attestor. The --public-key-id-override tells bunauthz to
# accept attestations that assert the given override as their publicKeyId.
# Without this override, binauthz by default expects the publicKeyId to use
# prefix "//cloudkms.googleapis.com/v1" rather than "gcpkms://". See the
# definition of KMS_URI in env.sh.
${gcloud} container binauthz attestors public-keys add \
    --attestor="${ATTESTOR_NAME}" \
    --keyversion-project="${KEY_PROJECT}" \
    --keyversion-location="${LOCATION}" \
    --keyversion-keyring="${KEYRING}" \
    --keyversion-key="${KEY}" \
    --keyversion="${KEY_VERSION}" \
    --public-key-id-override="${KMS_URI}"

# Set up binauth policy
# https://codelabs.developers.google.com/codelabs/cloud-binauthz-intro/index.html#3
policydir=$(mktemp -d)
policy="${policydir}/policy.yaml"
envsubst < "${dir}/policy.yaml" > "${policy}"
${gcloud} container binauthz policy import "${policy}"
rm -rf "${policydir}"

# Create cluster with binauthz enabled.
${gcloud} container clusters create \
    --binauthz-evaluation-mode=PROJECT_SINGLETON_POLICY_ENFORCE \
    --image-type="COS_CONTAINERD" --enable-image-streaming \
    --num-nodes=1 --zone="${ZONE}" --machine-type="e2-micro" "${PROD_CLUSTER}"
