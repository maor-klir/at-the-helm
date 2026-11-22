#helm #oci #repositories

# OCI registries and classic chart repositories

Helm downloads packaged charts from two kinds of storage: classic chart repositories, HTTP servers with an `index.yaml`, and OCI-based registries, the container registries that also store images.
The registries documentation recommends the second: *"It is recommended to use container registries with OCI support to store and share chart packages."*

## Classic chart repositories

The Chart Repository Guide describes a repository as *"a location where packaged charts can be stored and shared."*
It is a set of static files, so any HTTP server can host it, such as GitHub Pages or an object storage bucket.

**The index defines the repository:** *"A valid chart repository must have an index file."*
`helm repo index` generates it from a directory of packaged charts, and each entry holds the chart's `Chart.yaml` metadata, a `digest`, and its download `urls`.

**The archives can be stored elsewhere:** *"It is not required that a chart package be located on the same server as the `index.yaml` file."*
Bitnami's index uses this: 5,083 of its 19,167 download URLs start with `oci://`, so `bitnami/postgresql` 16.2.2 downloads from `registry-1.docker.io/bitnamicharts` (see **51 - Chart dependencies**).

**The client keeps a copy of every index:** `helm repo add` and `helm repo update` download the whole `index.yaml` into `~/.cache/helm/repository/`, and `helm search repo` reads only that copy.
Bitnami's index is 27.6 MB, and `helm dependency update` downloads every configured index again unless `--skip-refresh` is set.

## OCI-based registries

A registry that implements the OCI distribution specification stores a chart the way it stores an image: as a manifest that lists a config blob and layers, under a repository name and a tag.
The registries documentation: *"An OCI-based registry can contain zero or more Helm repositories and each of those repositories can contain zero or more packaged Helm charts."*

**Each chart is a repository of its own:** in `oci://localhost:5000/helm-charts/mychart:0.1.0`, `localhost:5000` is the registry, `helm-charts` a namespace, `mychart` the chart's name, and `0.1.0` its version as the tag.
`helm push` takes the reference without the last two parts: *"The registry reference basename is inferred from the chart's name, and the tag is inferred from the chart's semantic version."*

A `helm create` chart pushed to a local registry has a manifest with these parts:

| Part | Media type | Content (from Helm's source) |
|---|---|---|
| config | `application/vnd.cncf.helm.config.v1+json` | the chart's metadata as JSON |
| layer | `application/vnd.cncf.helm.chart.content.v1.tar+gzip` | the `.tgz` that `helm package` wrote |
| optional layer | `application/vnd.cncf.helm.chart.provenance.v1.prov` | the provenance file, pushed when it sits next to the `.tgz` |

The manifest also carries annotations such as `org.opencontainers.image.title` and `org.opencontainers.image.version`, set from the chart's name and version.

**Tags can't hold a `+`:** the OCI distribution specification allows only `[a-zA-Z0-9_][a-zA-Z0-9._-]{0,127}` in a tag, so `helm push` stores version `0.1.1+build.7` under the tag `0.1.1_build.7` and prints:

```text
OCI artifact references (e.g. tags) do not support the plus sign (+). To support
storing semantic versions, Helm adopts the convention of changing plus (+) to
an underscore (_) in chart version tags when pushing to a registry and back to
a plus (+) when pulling from a registry.
```

**Versions come from the tag list:** a registry has no index, so for a version range or no version, Helm lists the repository's tags, keeps the ones that parse as semantic versions, and takes the highest match (from Helm's source, `pkg/registry`).
With tags `0.1.0` and `0.1.1_build.7`, `helm show chart` without `--version` pulled `0.1.1_build.7`, and a dependency on `~0.1.0` resolved to `0.1.1+build.7`.

## The same tasks in each

| Task | Classic repository | OCI registry |
|---|---|---|
| Register it | `helm repo add bitnami https://charts.bitnami.com/bitnami` | nothing to register |
| Log in | `helm repo add` with `--username` and `--password` | `helm registry login <host>` |
| Search | `helm search repo`, against the local index | no `helm search`; Artifact Hub indexes OCI repositories |
| Install | `helm install pg bitnami/postgresql --version 16.2.2` | `helm install pg oci://registry-1.docker.io/bitnamicharts/postgresql --version 16.2.2` |
| Publish | `helm package`, `helm repo index`, then upload the archive and the index | `helm package`, then `helm push <tgz> oci://<registry>/<namespace>` |
| Declare a dependency | `repository: https://charts.bitnami.com/bitnami`, or `@bitnami` | `repository: oci://registry-1.docker.io/bitnamicharts` |
| Sign | a GPG provenance file next to the archive | the provenance layer, or Sigstore through the `helm-sigstore` plugin |

**An OCI registry can't be added as a repository:** the quickstart says of `oci://` installs, *"This approach doesn't require adding a repository first."*
`helm repo add` refuses one:

```text
Error: looks like "oci://registry-1.docker.io/bitnamicharts" is not a valid chart repository or cannot be reached: failed to perform "FetchReference" on source: invalid reference
```

The registries documentation lists the commands that accept `oci://`: `helm pull`, `push`, `show`, `template`, `install`, and `upgrade`; `helm dependency update` also pulls from `oci://` repositories in `Chart.yaml`.
A dependency's `repository` *"is specified as the registry reference without the basename"*, like the `helm push` target.

**Artifact Hub lists OCI charts one by one:** *"Artifact Hub is able to process chart repositories stored in OCI registries."*
Its URL format names the chart itself, `oci://registry/namespace/chart-name`, while a classic repository is added once with all its charts.

## Logging in

`helm registry login` takes a host, not a URL: *"The host must be only the registry hostname, optionally with a port."*
The command reference shows it for GitHub's registry, with the token on standard input:

```bash
echo "$GITHUB_TOKEN" | helm registry login ghcr.io -u $GITHUB_USER --password-stdin
```

Helm stores the credentials in `~/.config/helm/registry/config.json`, the path in `HELM_REGISTRY_CONFIG`.
For a host that file doesn't list, Helm's source shows a fallback to Docker's credential store, the one `docker login` writes to.

**Plain HTTP has to be requested:** a registry without TLS needs `--plain-http`, even on `localhost`.
Without it, `helm push` to a local registry fails:

```text
Error: failed to perform "Exists" on destination: Head "https://localhost:5000/v2/helm-charts/mychart/manifests/sha256:233a4b2d99733492743bd2c7feef23fdb1519f218b0d9aa538828b7ce7986672": http: server gave HTTP response to HTTPS client
```

## Tags and digests

**A tag can be moved:** pushing a changed chart as `0.1.0` again replaced the tag's digest, `sha256:233a…` with `sha256:62d3…`, with no warning.
The registries documentation: *"Installing a chart with a digest is more secure than a tag because digests are immutable."*

**Installs can pin a digest:** the reference ends in `@sha256:…`, alone or after the tag, and the Helm 4 overview states, *"Charts with non-matching digests are not installed."*
A tag combined with another chart's digest fails before rendering:

```text
Error: chart reference digest mismatch: sha256:233a4b2d99733492743bd2c7feef23fdb1519f218b0d9aa538828b7ce7986672 is not sha256:294d497d5bd1dc062a543782d2eb89dbe5da75e5502ea482a980141da79a6065
```

**`Chart.lock` records versions, not digests:** the lock for the `~0.1.0` dependency holds `version: 0.1.1+build.7` and no digest of the archive.
`helm dependency build` downloads whatever that tag points to when it runs.

## Moving to a registry

The registries documentation describes the move from a classic repository as `helm pull` for each chart version, then `helm push` of the resulting archives.
Installs then change from `repo/chart` references to `oci://` references, and dependencies change their `repository` to the `oci://` form.

Bitnami went this way: its chart READMEs document only `oci://registry-1.docker.io/bitnamicharts`, and its classic index sends 5,083 downloads into that registry.
