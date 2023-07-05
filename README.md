# Tekton on GCP
This repo demonstrates a scripted setup of Tekton on GCP, from standup through end-to-end
build-and-push of container to AR.

1. Set up a GCP project, including billing setup.
2. Make sure you have Cloud SDK, `kubectl`, `ko`, and `tkn` (Tekton CLI) installed.
3. You also need the `envsubst` tool (which is typically part of the `gettext` package).
4. Clone this repo.
5. `export PROJECT=<the-project-you-set-up>`
   Optional: `export KEY_PROJECT=<project-for-kms>` if you want to store your
   keys separately. See: https://cloud.google.com/kms/docs/separation-of-duties
6. `./setup.sh`
7. When `setup.sh` completes, `run_pipeline.sh` will build and push a container.
8. Provenance will be captured in Container Analysis, and the `./verify_*`
   scripts can be used to verify `kms` signatures.

NOTE: When you run `setup.sh`, a new `kubectl` configuration will be created and
will be your active context when `setup.sh` completes.

## Example

```shell
export PROJECT=my-project-name
gcloud projects create ${PROJECT}
gcloud beta billing projects link ${PROJECT} --billing-account=${BILLING_ACCOUNT}
./setup.sh
./run_pipeline.sh
```

## Verify signatures

Run `verify_provenance.sh` to verify the signed provenance with `kms`.

Run `verify_attestation.sh` to verify the signed attestation with `kms`.

NOTE:
- To verify signatures, you must first install `cosign` and `jq`.
- To authenticate with `cosign`, you need Application Default Credentials, which
  you can put into place via `gcloud auth application-default login`.
  -  See: https://cloud.google.com/sdk/gcloud/reference/auth/application-default
- This (unfortunately obscure) error indicates that you need to authenticate
  with ADC:

  ```
  Error: verifying blob: <details>: loading public key: loading URL: unrecognized scheme: gcpkms://
  ```

# Next Steps

For more advanced GKE configuration information, see https://github.com/bendory/tekton-gke.
