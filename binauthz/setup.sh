#!/bin/sh
set -e

dir=$(dirname $0)
. "${dir}"/env.sh

# These APIs should all have been enabled during Tekton installation, so this
# should be a no-op.
${gcloud} services enable artifactregistry.googleapis.com \
    cloudkms.googleapis.com \
    compute.googleapis.com \
    container.googleapis.com \
    containeranalysis.googleapis.com \
    containerfilesystem.googleapis.com \
    iam.googleapis.com

# Enable default GKE service account to pull images from AR.
PROJECT_NUMBER=$(${gcloud} projects describe $PROJECT --format='value(projectNumber)')
${gcloud} projects add-iam-policy-binding $PROJECT \
    --role=roles/artifactregistry.reader \
    --member=serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com

# Enable binauth API and set up a cluster with binauthz enabled.
${gcloud} services enable binaryauthorization.googleapis.com

# Set up binauth policy
policydir=$(mktemp -d)
policy="${policydir}/policy.yaml"
cp "${dir}/policy.yaml" "${policy}"
echo "- namePattern: ${LOCATION}-docker.pkg.dev/${PROJECT}/${REPO}/${IMAGE}" >> "${policy}"
${gcloud} container binauthz policy import "${policy}"
rm -rf "${policydir}"

# Create cluster with binauthz enabled.
${gcloud} container clusters create --enable-binauthz \
    --image-type="COS_CONTAINERD" --enable-image-streaming \
	--region="${REGION}" --machine-type="e2-micro" "${CLUSTER}"
