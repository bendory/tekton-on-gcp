# tekton-gcp-setup
Script setup of Tekton on GCP, from standup through end-to-end build-and-push of container to AR.

1. Set up a GCP project, including billing setup.
2. Make sure you have Cloud SDK, `kubectl`, and `tkn` (Tekton CLI) installed.
3. Clone this repo.
4. `export PROJECT=<the-project-you-set-up>`
5. `./setup.sh`
