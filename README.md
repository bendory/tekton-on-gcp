# Tekton on GCP
Script setup of Tekton on GCP, from standup through end-to-end build-and-push of container to AR.

1. Set up a GCP project, including billing setup.
2. Make sure you have Cloud SDK, `kubectl`, `ko`, and `tkn` (Tekton CLI) installed.
3. Clone this repo.
4. `export PROJECT=<the-project-you-set-up>`
5. `./setup.sh`

NOTE: When you run `setup.sh`:
- A new `gcloud` configuration named "tekton-setup" will be created and populated.
- A new `kubectl` configuration will be created.
- Both of these configurations will be active when `setup.sh` completes.

## Example

```shell
export PROJECT=my-project-name
gcloud projects create ${PROJECT}
gcloud beta billing projects link ${PROJECT} --billing-account=${BILLING_ACCOUNT}
./setup.sh
```

## Some helper commands

Extract provenance details about the built image:

```shell
export IMAGE_URL=$(tkn tr describe --last -o jsonpath="{.status.taskResults[1].value}")
export IMAGE_DIGEST=$(tkn tr describe --last -o jsonpath="{.status.taskResults[0].value}")

alias gcurl='curl -X GET -H "Content-Type: application/json" -H "Authorization: Bearer $(gcloud auth print-access-token)"'
gcurl https://containeranalysis.googleapis.com/v1/projects/$PROJECT/occurrences\?filter\="resourceUrl=\"$IMAGE_URL@$IMAGE_DIGEST\"%20AND%20kind=\"BUILD\""
```
