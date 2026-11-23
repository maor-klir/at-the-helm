#helm #kubernetes #images

# The application image

This repository is about Helm, and config-store's image matters here as the one input a chart can't create: Kubernetes runs images, it never builds them.
The image is `ghcr.io/maor-klir/config-store:1.0.0`, built from the Dockerfile's `production` stage and pushed to the GitHub Container Registry.

What the application expects at startup is in **41 - The config-store application**, and the rest of the Compose setup's path to a chart in **42 - From Compose to a Helm chart**.

## From image reference to chart values

An image reference has a registry host, a repository, and a tag or a digest:

| Part | config-store | Without it |
|---|---|---|
| Registry host | `ghcr.io` | Docker Hub: *"If you don't specify a registry hostname, Kubernetes assumes that you mean the Docker public registry."* |
| Repository | `maor-klir/config-store` | required |
| Tag | `1.0.0` | `latest` |
| Digest | `@sha256:cdfbf626…` | the tag decides |

The `config-store` chart assembles the reference from two values, with the chart's `appVersion` as the fallback tag:

```yaml
image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
```

With `--set image.repository=ghcr.io/maor-klir/config-store`, it renders `image: "ghcr.io/maor-klir/config-store:1.0.0"`, because the chart's `values.yaml` sets `tag: '1.0.0'`, which matches its `appVersion: '1.0.0'`.

## Fixed tags and digests

Helm's best practices rule out moving tags: *"A container image should use a fixed tag or the SHA of the image. It should not use the tags `latest`, `head`, `canary`, or other tags that are designed to be "floating"."*

**A tag can move, a digest can't:** the Kubernetes documentation explains, *"Tags can be moved to point to different images, but digests are fixed."*
The chart's default `pullPolicy` is `IfNotPresent`, *"the image is pulled only if it is not already present locally."*, so a node that already has `1.0.0` keeps running its copy even if the tag is pushed again.

A new build therefore gets a new tag, such as `1.0.1`, and the chart's `appVersion` and `image.tag` follow it.
The chart's template also accepts a digest through `image.tag`: `--set image.tag=1.0.0@sha256:cdfbf626…` renders `ghcr.io/maor-klir/config-store:1.0.0@sha256:cdfbf626…`.

## Platform and access

**The image's platform has to match the nodes':** config-store is built for `linux/amd64`, the architecture `kubectl get nodes` reports for all three k3d-argocd nodes.
An image without a matching platform can't run on the node.

**A public package needs no pull Secret:** GHCR packages start private, and in GHCR *"public packages allow anonymous access and can be pulled without authentication or signing in via the CLI."*
For a private image, the chart's `imagePullSecrets` value lists the Secret with the registry credentials, which Kubernetes uses when the Pod pulls the image.

## Verify

The pushed image, its manifests, and an anonymous pull:

```bash
docker buildx imagetools inspect ghcr.io/maor-klir/config-store:1.0.0
DOCKER_CONFIG=$(mktemp -d) docker pull ghcr.io/maor-klir/config-store:1.0.0
```

The first lists a `linux/amd64` manifest and the build's attestation manifest, `unknown/unknown`; the second pulls the image without credentials.

From `05-chart-dependencies-subcharts/01-bootstrap-config-store-chart`, the chart with the image:

```bash
helm template config-store subcharts/config-store -s templates/deployment.yaml | grep -E 'image(PullPolicy)?:'
```

```text
          image: "ghcr.io/maor-klir/config-store:1.0.0"
          imagePullPolicy: IfNotPresent
```
