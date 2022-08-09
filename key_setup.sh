#!/bin/sh
# This script sets up the KMS key used for signing. It is separate from setup.sh
# because it is a best practice to use a separate project for keys to better
# enforce separation of duties:
# https://cloud.google.com/kms/docs/separation-of-duties
#
# Given the above, the assumption is that users of a single key project will
# execute this script only once.
#
# Users of a single project for keys and Tekton should run this script once
# prior to running setup.sh.
set -e

dir=$(dirname $0)
. "${dir}"/env.sh

# Configure Key Management Service. Set up a private key that will be used by
# VERIFIER_SA to sign attestations.
${key_gcloud} services enable cloudkms.googleapis.com # Ensure KMS is available.
${key_gcloud} kms keyrings create "${KEYRING}" --location "${LOCATION}"
