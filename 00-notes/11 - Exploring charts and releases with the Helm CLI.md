#helm #kubernetes

# Exploring charts and releases with the Helm CLI

Most Helm commands we run around an install only read information.
They split by what they read: `helm repo` and `helm search` work with chart repositories, `helm show` reads a chart, and `helm list`, `helm status`, and `helm get` read a release in the cluster.
`helm install` connects the two halves: it turns a chart into a release.

| Command | Reads | Talks to the cluster |
|---|---|---|
| `helm repo add`, `list`, `update` | the local repository list and index cache | no |
| `helm search repo` | the local index cache | no |
| `helm search hub` | Artifact Hub | no |
| `helm show` | a chart in a repository, an OCI registry, or a local path | no |
| `helm install` | a chart, then writes a release | yes |
| `helm list`, `status`, `get` | the release record | yes |

## Chart repositories: `helm repo`

Helm's Using Helm guide describes the group: *"The `helm repo` command group provides commands to add, list, and remove repositories."*
`helm repo add` stores a name and a URL, and later commands refer to a chart as `<repo-name>/<chart>`, as in `bitnami/wordpress`.

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo list
helm repo update
```

**The list and the cache are local files:** the global flags describe `~/.config/helm/repositories.yaml` as the *"path to the file containing repository names and URLs"* and `~/.cache/helm/repository` as the *"path to the directory containing cached repository indexes"*.
Each added repository gets its own index file there, e.g. `bitnami-index.yaml`.
`helm repo remove <name>` deletes an entry.

`helm repo update` refreshes the cache: *"Update gets the latest information about charts from the respective chart repositories. Information is cached locally, where it is used by commands like 'helm search'."*
It also accepts repository names, so `helm repo update bitnami` refreshes only one.

**`helm install` reads the same cache:** in Helm's source, a reference like `bitnami/wordpress` is resolved against the cached index file, not the live repository.
A version published after our last `helm repo update` doesn't exist for `helm install` or `helm show`, and pinning it fails with an error that ends in `(try 'helm repo update')`.

**OCI registries need no `helm repo add`:** a chart in an OCI registry is referenced directly as `oci://<registry>/<path>/<chart>`.
Helm's registry documentation says *"Support for the `oci://` protocol is also available in various other subcommands"* and lists `helm pull`, `helm push`, `helm show`, `helm template`, `helm install`, and `helm upgrade`.
`helm search` is not on the list.

## Finding charts: `helm search`

The Using Helm guide names the two sources:

> *"`helm search hub` searches the Artifact Hub, which lists helm charts from dozens of different repositories."*
>
> *"`helm search repo` searches the repositories that you have added to your local helm client (with `helm repo add`). This search is done over local data, and no public network connection is needed."*

**`helm search repo` shows one version per chart:** the reference page says *"It will display the latest stable versions of the charts found."*
`--versions` (`-l`) prints every version on its own line, and `--version` filters by a semantic version constraint.

```bash
helm search repo wordpress
helm search repo bitnami/wordpress --versions
helm search repo bitnami/wordpress --version '~23.1.0'   # latest 23.1.x: 23.1.29
```

The keyword doesn't have to be exact: *"Helm search uses a fuzzy string matching algorithm, so you can type parts of words or phrases"*.

**`helm search hub` prints Artifact Hub pages, not repositories:** *"`helm search hub` exposes the URL to the location on artifacthub.io but not the actual Helm repo."*
`--list-repo-url` adds a `REPO URL` column with the address to pass to `helm repo add`, or the `oci://` reference to use directly.

## Inspecting a chart: `helm show`

`helm show` reads a chart without installing it.
Each subcommand prints one part of the chart, and `helm show all` prints them together:

| Subcommand | Prints |
|---|---|
| `helm show chart` | `Chart.yaml`: name, version, appVersion, dependencies |
| `helm show values` | `values.yaml`, with its comments |
| `helm show readme` | the README |
| `helm show crds` | the CustomResourceDefinition files |
| `helm show all` | *"all its content (values.yaml, Chart.yaml, README)"* |

**The two version numbers move independently:** `version` is the chart's own version, and `appVersion` is the version of the application it deploys (see **01 - The role of Helm in Kubernetes**).
WordPress charts 23.1.20 and 23.1.28 both deploy WordPress 6.6.2, yet the rendered image moves from `6.6.2-debian-12-r7` to `6.6.2-debian-12-r18`.
The 34.x charts deploy WordPress 7.1.

**Without `--version`, Helm reads the latest version:** the reference pages say *"If this is not specified, the latest version is used"*.
`helm show values bitnami/wordpress` prints the values of the latest chart, 34.x, not of the 23.1.20 we installed, so we pass the version we want:

```bash
helm show chart bitnami/wordpress --version 23.1.20
helm show values bitnami/wordpress --version 23.1.20
```

**`helm show values` can filter its output:** the reference page describes `--jsonpath` as *"supply a JSONPath expression to filter the output"*.

```bash
helm show values bitnami/wordpress --version 23.1.20 --jsonpath '{.service.type}'
# LoadBalancer
```

## Installing: `helm install`

Our WordPress install pins the chart version, uses its own namespace, and passes a values file:

```bash
helm -n wordpress install local-wp bitnami/wordpress --version 23.1.20 \
  --create-namespace \
  --values ./wp-repo-overrides.yaml
```

`local-wp` is the release name, and `--create-namespace` does what the reference page says: *"create the release namespace if not present"*.
`--values` (`-f`) can *"specify values in a YAML file or a URL (can specify multiple)"*.
The chart reference forms `helm install` accepts, and the release record it writes, are in **01 - The role of Helm in Kubernetes.**

## Inspecting a release: `helm list`, `helm status`, and `helm get`

**Release commands work in one namespace:** `helm list` *"uses current namespace context if namespace not specified"*, and `helm status` and `helm get` use the same namespace.
Our kubeconfig context sets no namespace, so Helm looks in `default`, and `helm get values local-wp` fails with `Error: release: not found`.
We pass `-n wordpress`, or use `helm list -A` to *"list releases across all namespaces"*.

`helm status` gives a summary of one release.
The Using Helm guide puts it this way: *"To keep track of a release's state, or to re-read configuration information, you can use `helm status`"*.
In Helm 4.3.1 it prints the last deployment time, namespace, status, revision, and description, followed by the release's resources, the last test run, and the chart's notes.

### `helm get`

The reference page describes `helm get` as *"multiple subcommands which can be used to get extended information about the release"*:

| Subcommand | Reference description |
|---|---|
| `helm get values` | *"This command downloads a values file for a given release."* |
| `helm get notes` | *"This command shows notes provided by the chart of a named release."* |
| `helm get metadata` | *"This command fetches metadata for a given release"* |
| `helm get manifest` | *"This command fetches the generated manifest for a given release."* |
| `helm get hooks` | *"This command downloads hooks for a given release."* |
| `helm get all` | *"a human readable collection of information about the notes, hooks, supplied values, and generated manifest file of the given release"* |

Every subcommand takes `--revision` to read an earlier revision instead of the current one.
`values` and `metadata` also take `-o json` or `-o yaml`, and `helm get --help` lists the subcommands.

**`helm get values` prints only the values we supplied:** the output starts with `USER-SUPPLIED VALUES:` and holds what was passed with `--values` and `--set`.
For our release, that is the image overrides file:

```text
USER-SUPPLIED VALUES:
image:
  repository: bitnamilegacy/wordpress
mariadb:
  image:
    repository: bitnamilegacy/mariadb
```

A release installed without any values prints `null` instead.
That follows from Helm's source: the release record's `config` field is tagged `json:"config,omitempty"`, so an empty value set isn't stored at all.

**`--all` prints the computed values:** the reference page calls it *"dump all (computed) values"*, and the output starts with `COMPUTED VALUES:`.
In Helm's source, `--all` coalesces the chart's default values with the user-supplied ones, subchart values included.
For our release that is 794 lines, with the MariaDB subchart's values under `mariadb:`.

**`helm show values` and `helm get values --all` answer different questions:** the first prints a chart version's `values.yaml` file, comments included, from the repository.
The second prints the merged values of a release in the cluster, the ones its templates were rendered with.

**`helm get notes` prints the install notes again:** the chart's `templates/NOTES.txt` is rendered at install time, and Helm's source keeps the result in the release record's `info.notes` field.
The chart template guide describes the file: *"At the end of a `helm install` or `helm upgrade`, Helm can print out a block of helpful information for users."*
`helm get notes` shows that same text without reinstalling.

**`helm get metadata` summarizes the release:** chart name and version, app version, namespace, revision, status, and deployment time.
Helm 4 adds two fields that the Helm 3.22.1 source doesn't print.
`LABELS` shows the labels on the release record's Secret, and `APPLY_METHOD` shows how the objects were applied, here `server-side apply` (see **02 - Benefits and limitations of Helm**).

```text
NAME: local-wp
CHART: wordpress
VERSION: 23.1.20
APP_VERSION: 6.6.2
LABELS: modifiedAt=1792953387,name=local-wp,owner=helm,status=deployed,version=1
DEPENDENCIES: common,mariadb
NAMESPACE: wordpress
REVISION: 1
STATUS: deployed
DEPLOYED_AT: 2026-10-25T19:36:26+01:00
APPLY_METHOD: server-side apply
```

The multi-line `ANNOTATIONS` field, printed after `APP_VERSION`, is left out above.
It holds the chart's own annotations, including the image list the chart was published with, `docker.io/bitnami/wordpress:6.6.2-debian-12-r7`, not the `bitnamilegacy` image we override it with.

**`helm get manifest` prints the objects Helm applied:** the rendered templates, as one YAML stream.
`helm get hooks` prints nothing for this release, because WordPress 23.1.20 defines no hooks.

## Verify

Our release is `local-wp` in the `wordpress` namespace:

```bash
helm -n wordpress list
helm -n wordpress status local-wp
```

The values we supplied, then the full computed set:

```bash
helm -n wordpress get values local-wp
helm -n wordpress get values local-wp --all | wc -l      # 794
```

The notes and the metadata, including Helm 4's apply method:

```bash
helm -n wordpress get notes local-wp
helm -n wordpress get metadata local-wp -o yaml | grep applyMethod   # applyMethod: ssa
```

The kinds of objects in the manifest:

```bash
helm -n wordpress get manifest local-wp | grep '^kind:' | sort | uniq -c
```

The `LABELS` field matches the labels on the release record's Secret:

```bash
kubectl -n wordpress get secret -l owner=helm --show-labels
```
