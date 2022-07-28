# Binary Authorization
This directory demonstrates a scripted setup of [Binary
Authorization](https://cloud.google.com/binary-authorization) on GKE.
Before coming here, you should have run `../setup.sh` (in the parent directory)
and the assets created by that script should still be standing.

1. `../setup.sh` (in the parent directory) creates a `tekton` cluster where
   your demo CI/CD pipelines live.
2. Run `./setup.sh` herein to stand up a new `prod` cluster with Binary
   Authorization enabled. This is where your production assets are 
   deployed in this demo.
3. Run `./build.sh`; this will use the existing Tekton installation build a new
   image called `allow` in Artifact Registry.
4. You can deploy this image to your `prod` cluster by running `./deploy.sh`.
   The deploy script will also attempt to deploy a disallowed image. It will
   then run `kubectl get deployments` (where you will see only one of the
   deployments running) and then `kubectl get events` where you will see the
   `deny` message.

## Example output

`kubectl get deployments`

	NAME      READY   UP-TO-DATE   AVAILABLE   AGE
	allowed   1/1     1            1           98s
	blocked   0/1     0            0           98s


`kubectl get events | grep "${REPO}"`

	2m21s       Normal    Pulling                   pod/allowed-7cb4c6b8bf-62nhr               Pulling image "us-docker.pkg.dev/bendory-20220727-b/my-repo/allow"
	2m21s       Normal    Pulled                    pod/allowed-7cb4c6b8bf-62nhr               Successfully pulled image "us-docker.pkg.dev/bendory-20220727-b/my-repo/allow" in 794.767724ms
	3m13s       Warning   FailedCreate              replicaset/blocked-7cf5d6986c              Error creating: admission webhook "imagepolicywebhook.image-policy.k8s.io" denied the request: Image us-docker.pkg.dev/bendory-20220727-b/my-repo/deny denied by Binary Authorization cluster admission rule for us-central1.prod. Denied by always_deny admission rule
	2m21s       Normal    ImageStreaming            node/gke-prod-default-pool-97e39836-xrvs   Image us-docker.pkg.dev/bendory-20220727-b/my-repo/allow:latest is backed by image streaming.
