# Tekton on GCP
Script setup of Tekton on GCP, from standup through end-to-end build-and-push of container to AR.

1. Set up a GCP project, including billing setup.
2. Make sure you have Cloud SDK, `kubectl`, `ko`, and `tkn` (Tekton CLI) installed.
3. Clone this repo.
4. `export PROJECT=<the-project-you-set-up>`
5. `./setup.sh`
6. When `setup.sh` completes, `run_pipeline.sh` will build and push a container.
7. Provenance will be captured in Container Analysis, and the `./verify_*`
   scripts can be used to verify `kms` signatures.

NOTE: When you run `setup.sh`,a new `kubectl` configuration will be created and
will be active when `setup.sh` completes. The other scripts assume that
configuration is the active configuration.

## Example

```shell
export PROJECT=my-project-name
gcloud projects create ${PROJECT}
gcloud beta billing projects link ${PROJECT} --billing-account=${BILLING_ACCOUNT}
./setup.sh
./run_pipeline.sh
```

## Verify signatures

NOTE:
- To verify signatures, install `cosign` and `jq`.
- To authenticate with `cosign`, you need Application Default Credentials, which
  you can put into place like this: `gcloud auth application-default login`.
  This is different from `gcloud auth login`.
  The error if you need to login with ADC looks like this:

  ```
  Error: verifying blob: <details>: loading public key: loading URL: unrecognized scheme: gcpkms://
  ```

Run `verify_provenance.sh` to verify the signed provenance with `kms`.

Run `verify_attestation.sh` to verify the signed attestation with `kms`.
