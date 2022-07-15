# Tekton on GCP
Script setup of Tekton on GCP, from standup through end-to-end build-and-push of container to AR.

1. Set up a GCP project, including billing setup.
2. Make sure you have Cloud SDK, `kubectl`, and `tkn` (Tekton CLI) installed.
3. Clone this repo.
4. `export PROJECT=<the-project-you-set-up>`
5. `./setup.sh`

NOTE: When you run `setup.sh`:
- A new `gcloud` configuration named "tekton-setup" will be created and populated.
- A new `kubectl` configuration will be created.
- Both of these configurations will be active when `setup.sh` completes.

## Example

```
export PROJECT=my-project-name
gcloud projects create ${PROJECT}
gcloud beta billing projects link ${PROJECT} --billing-account=${BILLING_ACCOUNT}
./setup.sh
```
