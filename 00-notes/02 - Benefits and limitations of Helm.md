#helm #kubernetes

# Benefits and limitations of Helm

Helm adds three things on top of Kubernetes: charts, releases, and templates (see **01 - The role of Helm in Kubernetes**).
Each one brings a benefit and a limitation that comes from the same mechanism.

Templates make a chart configurable, and they also make it harder to read.
A public chart can be installed by anyone, so it has to be reviewed before it runs.
The release record gives Helm its history, and it is one more piece of state in the cluster that can be deleted or fall out of date.

The sections below describe each benefit, each limitation, and what addresses the limitation.

## Benefits

### One command for every object in the application

`helm install`, `helm upgrade`, `helm rollback`, and `helm uninstall` act on every object the chart renders, not on one manifest at a time.
A chart version that changes the Deployment, the ConfigMap, and the NetworkPolicy together is applied with one command:

```bash
helm upgrade my-app ./app-chart-2.2.0.tgz -f values-prod.yaml --namespace prod
```

The same applies to patches.
A patch version of a chart that only changes an image tag for a security fix reaches every workload that uses that image through the same `helm upgrade`.

### The same chart in every environment

Each environment is a values file for the same chart.
A chart can also check those values before anything is sent to the cluster.
The chart documentation describes the schema file:

> *"Sometimes, a chart maintainer might want to define a structure on their values. This can be done by defining a schema in the `values.schema.json` file."*

*"Validation occurs when any of the following commands are invoked:"* `helm install`, `helm upgrade`, `helm lint`, and `helm template`.
With a schema that declares `port` as an integer and `protocol` as required, a values file that sets `port: "80"` and leaves out `protocol` stops the command before anything is rendered:

```text
Error: values don't meet the specifications of the schema(s) in the following chart(s):
app-chart:
- at '': missing property 'protocol'
- at '/port': got string, want integer
```

### Upgrades and rollbacks of the whole release

Every `helm upgrade` records a new revision, `helm history my-app` lists them, and `helm rollback` returns the release to an earlier one.
Without a revision number it uses the previous one: *"If this argument is omitted or set to 0, it will roll back to the previous release."*

An upgrade can also roll itself back when it fails.
Helm 4 calls the flag `--rollback-on-failure`; Helm 3's `--atomic` still works but is deprecated.
The `helm upgrade` reference describes it:

> *"if set, Helm will rollback the upgrade to previous success release upon failure. The --wait flag will be defaulted to "watcher" if --rollback-on-failure is set"*

The history is limited by `--history-max` on `helm upgrade` and `helm rollback`, described as *"limit the maximum number of revisions saved per release. Use 0 for no limit (default 10)"*, so a rollback can only target one of the last ten revisions unless the limit is raised.

### Shared charts and their documentation

Public charts are listed on Artifact Hub, and teams publish internal charts to a private chart repository or an OCI registry.
A chart published once lets every other team install the same reviewed manifests, with the same labels, probes, and security settings, instead of writing their own.

A chart carries its own documentation.
The chart documentation says a `README.md` *"should generally contain"* a description of the application, its prerequisites, the options in `values.yaml` with their defaults, and anything else relevant to installing or configuring it.
Hubs display that file: *"When hubs and other user interfaces display details about a chart that detail is pulled from the content in the `README.md` file."*

`templates/NOTES.txt` is printed after `helm install` and by `helm status`.
The best practices also ask for every value to be documented in `values.yaml` itself:

> *"Every defined property in `values.yaml` should be documented. The documentation string should begin with the name of the property that it describes, and then give at least a one-sentence description."*

Both can be read before installing, with `helm show readme <chart>` and `helm show values <chart>`.

### Versioned packages

The chart version covers every manifest in the chart.
The chart documentation asks for Semantic Versioning 2: *"A version should follow the SemVer 2 standard but it is not strictly enforced."*
SemVer also forbids changing a version after it is released:

> *"Once a versioned package has been released, the contents of that version MUST NOT be modified. Any modifications MUST be released as a new version."*

`app-chart-2.1.0.tgz` installed in `dev` and in `prod` therefore holds the same templates, and promoting a change means installing the same chart version with another values file.

Dependencies are pinned the same way.
`helm dependency update` resolves the version ranges in `Chart.yaml`, and *"On successful update, this will generate a lock file that can be used to rebuild the dependencies to an exact version."*
`helm dependency build` rebuilds `charts/` from that `Chart.lock` without resolving the ranges again.

### Templates go beyond plain manifests and Kustomize

Templates decide at render time which objects and fields exist.
The `helm create` scaffold renders `templates/ingress.yaml` only when `{{- if .Values.ingress.enabled -}}` is true, and leaves `replicas` out of the Deployment when autoscaling is enabled:

```yaml
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
```

`range` loops over lists and maps from the values, and functions transform values as they are rendered.
Plain manifests have none of this, and Kustomize, being template-free, has no conditionals or loops.

## Limitations

### A learning curve

A chart has its own layout, and each part follows its own rules:

```text
app-chart/
  Chart.yaml          # required: apiVersion, name, version; also dependencies
  values.yaml         # default values
  values.schema.json  # optional schema for the values
  charts/             # dependencies, stored as chart archives
  crds/               # Custom Resource Definitions, not templated
  templates/          # templates rendered with the values
  templates/NOTES.txt # usage notes printed after install
```

**Only `Chart.yaml` is required:** *"The `Chart.yaml` file is required for a chart."*
Its required fields are `apiVersion`, `name`, and `version`, and a chart with no `values.yaml` still lints and renders.

Helm looks for that exact file name: on Linux, a chart with a `chart.yaml` stops `helm template` with `unable to detect chart`.
*"Helm reserves use of the `charts/`, `crds/`, and `templates/` directories, and of the listed file names."*

**`apiVersion: v2` is the chart format for Helm 3 and Helm 4:** *"The `apiVersion` field should be `v2` for Helm charts that require at least Helm 3."*
Helm 4.3.1 still renders `v1` charts written for Helm 2.

Charts v3 *"is in early development and available for experimentation"*: with `HELM_EXPERIMENTAL_CHART_V3=1`, `helm create --chart-api-version=v3` scaffolds a v3 chart, but `helm template` in Helm 4.3.1 still rejects it with `invalid chart apiVersion`.

The template language combines three sources.
Helm's documentation says so directly:

> *"While we talk about the "Helm template language" as if it is Helm-specific, it is actually a combination of the Go template language, some extra functions, and a variety of wrappers to expose certain objects to the templates."*

- **Go template syntax:** actions, pipelines, `if`, `range`, `with`, variables, and the dot, defined by Go's `text/template`
- **Sprig functions:** such as `default`, `trunc`, and `dict`
- **Helm's own functions and objects:** such as `include`, `tpl`, `required`, `toYaml`, `.Values`, `.Release`, and `.Files`

The rendered output must also be valid YAML, so whitespace control (`{{-`, `-}}`) and indentation functions such as `nindent` matter as much as the logic.
Errors come from two places: the renderer, for template and YAML mistakes, and the API server, for objects that render cleanly but are still invalid:

> *"Debugging templates can be tricky because the rendered templates are sent to the Kubernetes API server, which may reject the YAML files for reasons other than formatting."*

`helm lint` and `helm template --debug` render and check a chart locally.
`helm install --dry-run=server` also runs any `lookup` in the chart against the cluster.

### Over-templating

A simple application with one environment may not need a chart.
A few manifests applied with `kubectl apply -f`, or a Kustomize base with one overlay, have no templates to read and no release record to keep.
A chart adds `Chart.yaml`, `values.yaml`, helper templates, and a release history to maintain.

The opposite problem is a chart that exposes every field of every object as a value.
`values.yaml` then repeats the structure of the Kubernetes objects, each value adds a conditional or a default to a template, and the only way to know what the chart produces is to render it.
Helm's best practices prefer simpler values:

> *"In most cases, flat should be favored over nested. The reason for this is that it is simpler for template developers and users."*

A chart does not have to cover every option.
Post rendering exists for the cases it leaves out:

> *"This allows users with advanced configuration needs to be able to use tools like `kustomize` to apply configuration changes without the need to fork a public chart or requiring chart maintainers to specify every last configuration option for a piece of software."*

In Helm 4 a post-renderer is a plugin: `--post-renderer` takes *"the name of a postrenderer type plugin to be used for post rendering"*.

### Reviewing community charts

A chart renders whatever its templates define, and Helm creates it with the permissions of whoever runs `helm install`.
A public chart can contain ClusterRoles and ClusterRoleBindings, privileged containers, `hostPath` volumes, CRDs, and hook Jobs that run during the install.
Before installing, we read what the chart will create:

```bash
helm show values example/app --version 1.4.0
helm pull example/app --version 1.4.0 --untar
helm template my-app example/app --version 1.4.0 -f values.yaml --include-crds > rendered.yaml
grep '^kind:' rendered.yaml | sort | uniq -c
```

`helm template` leaves CRDs out unless `--include-crds` is given, and it includes hook manifests, such as a chart's test Pods, so the review covers them.
The images the manifests reference need the same check: who publishes them and which registry they are pulled from.

Artifact Hub shows who publishes a chart with two badges:

> *"The `Verified Publisher` status is automated and shows that the publisher has verified ownership of the repository. The `Official` status is manually granted and indicates that the publisher owns the software a package primarily focuses on."*

Artifact Hub also scans the images a package lists and shows the result on the package page: *"Security reports are generated using Trivy."*

Helm can check that a chart has not changed since its publisher signed it.
A signed chart has a provenance file next to the archive, and with `--verify`, *"the chart MUST have a provenance file, and the provenance file MUST pass all verification steps."*
The provenance documentation is explicit about failures: *"If a verification fails, there is reason to distrust the package."*

A valid signature proves who signed the chart, not that its contents are safe; the system *"hinges on the fact that you trust the person who signed the chart."*

For charts in OCI registries, Helm 4 also installs by digest, and *"Charts with non-matching digests are not installed."*

```bash
helm install my-app oci://registry.example.com/charts/app@sha256:<digest>
```

### The release record lives in the cluster

By default the release record is a set of Secrets in the release's namespace, one per revision.
`HELM_DRIVER` selects another backend: *"It can be set to one of the values: `[configmap, secret, sql]`."*
Wherever it is stored, it is the only record Helm has of the release.

**Deleting the record leaves the objects running:** Helm no longer knows the release exists.
`helm list` does not show it, `helm upgrade my-app` fails with `"my-app" has no deployed releases`, and every earlier revision is gone, so there is nothing to roll back to.

**Installing again recovers the release:** Helm's source shows that `helm install` adopts an existing object when its label `app.kubernetes.io/managed-by: Helm` and its annotations `meta.helm.sh/release-name` and `meta.helm.sh/release-namespace` match the new release.
Any other existing object stops the install with `exists and cannot be imported into the current release`.

`--take-ownership` skips that check, and the documentation lists this case among its uses: *"Recovering after annotations were removed or a release history was lost, so Helm no longer recognizes its own objects"*.
The new release starts again at revision 1; the lost history does not come back.

**RBAC cannot exclude the release Secrets from a broader grant:** *"Permissions are purely additive (there are no "deny" rules)."*
Anyone allowed to delete Secrets in the namespace can delete the release record, and the built-in `edit` role *"allows accessing Secrets"*.
Write access to Secrets in a release's namespace should therefore stay with the people and pipelines that run Helm.

**Removed Kubernetes API versions affect the stored manifests:** when Kubernetes removes an API version that a release's stored manifest still uses, the procedure in Helm's documentation changes the record itself: *"You need to edit the release manifest that is stored in the cluster to update the API versions to supported APIs."*

### Configuration drift

Helm compares and changes objects only while a Helm command runs.
Between commands nothing in Helm watches the release's objects, so `kubectl edit`, `kubectl scale`, `kubectl set image`, or a controller can change them while the release record still holds the manifests Helm last applied.
The cluster then runs a state that no revision describes.

Comparing the record with the live objects shows the difference:

```bash
helm get manifest my-app --namespace dev | kubectl diff --namespace dev -f -
```

The `kubectl diff` reference defines the result: *"Exit status: 0 No differences were found. 1 Differences were found. >1 Kubectl or diff failed with an error."*

What the next `helm upgrade` or `helm rollback` does with a changed field depends on how the release applies objects.
Helm 4 *"will default to server-side apply when installing a new Chart release"*, and *"When upgrading (or rolling back), Helm will by default follow the previous apply method of the release."*

| Apply method | Used by | A field changed outside Helm, at the next upgrade or rollback |
|---|---|---|
| Client-side, three-way merge | releases installed with Helm 3, or with `--server-side=false` | Helm's source builds the patch from the previous manifest, the new manifest, and the live object, so a field the chart sets is reset to the chart's value. Fields the chart never sets stay as they are. |
| Server-side apply | releases installed with Helm 4, or upgraded with `--server-side=true` | the field now belongs to the manager that changed it, so applying a different value is a conflict, and the upgrade fails unless `--force-conflicts` is set |

The Kubernetes server-side apply documentation states both rules: *"Whenever a field's value does change, ownership moves from its current manager to the manager making the change."* and *"Unless you specify a forced override, an apply operation that encounters field-level conflicts always fails"*.
Helm's source sends the whole rendered object on every upgrade and forces only when `--force-conflicts` is given.

After `kubectl patch` sets `replicas` to 2 on the Deployment of a server-side release, the next `helm upgrade` stops with an error that names the field and the manager that now owns it:

```text
Error: UPGRADE FAILED: conflict occurred while applying object dev/my-app apps/v1, Kind=Deployment: Apply failed with 1 conflict: conflict with "kubectl-patch" using apps/v1: .spec.replicas
```

`kubectl-patch` is the field manager name that `kubectl patch` records in the Deployment's `managedFields`.

**A failed upgrade still adds a revision:** `helm history my-app` lists revision 2 with status `failed` and the description `Upgrade "my-app" failed:` followed by the conflict.
Running the same upgrade with `--force-conflicts` deploys revision 3, sets `replicas` back to 1, and removes `kubectl-patch` from the Deployment's `managedFields`.

Some controllers change objects on purpose.
A HorizontalPodAutoscaler sets `spec.replicas` on its Deployment, which is why the `helm create` scaffold leaves `replicas` out when autoscaling is enabled (the template shown earlier in this note).
Helm never sets that field, so the autoscaler's value is neither reset nor in conflict.

Every other change belongs in the chart or its values and reaches the cluster through `helm upgrade`.

### Upgrades between chart versions

A new major version of a chart can need more than `helm upgrade`.
Semantic Versioning reserves the major version for this:

> *"Major version X (X.y.z | X > 0) MUST be incremented if any backward incompatible changes are introduced to the public API."*

For a chart, backward incompatible changes include a renamed or removed value, a changed default that changes the running application, a change to an immutable field, and a new major version of a database whose data has to be migrated.

The manual steps, when a publisher documents them, are in the chart's README; the Bitnami PostgreSQL chart's README, for example, has an `Upgrading` section with one entry per major version.
Artifact Hub lists a chart's changes per version from its `artifacthub.io/changes` annotation.

Helm itself leaves several things out of an upgrade:

- **CRDs:** *"There is no support at this time for upgrading or deleting CRDs using Helm."* If a CRD from `crds/` already exists, Helm skips it, so a new chart version with changed CRDs does not change the CRDs in the cluster.
- **Immutable fields:** the API server rejects a change to a field such as a Deployment's `spec.selector`, so the upgrade fails until the object is deleted and created again.
- **Data:** a rollback restores manifests, not the contents of volumes. A backup or a schema migration has to run as part of the upgrade, for example as a `pre-upgrade` hook, which *"Executes on an upgrade request after templates are rendered, but before any resources are updated"*.

Version ranges rely on publishers following SemVer.
The best practices suggest a patch-level range for dependencies, where *"`~1.2.3` is equivalent to `>= 1.2.3, < 1.3.0`"*, and a caret range such as `^1.2.3` allows every `1.x` version from `1.2.3` on.

A breaking change released as a minor or patch version falls inside the range, and the next `helm dependency update` brings it into the chart; `Chart.lock` keeps the previous versions only until that update runs.

When we publish our own charts, every breaking change gets a new major version.

## Benefits, limitations, and what addresses them

| Helm feature | Benefit | Limitation | What addresses the limitation |
|---|---|---|---|
| Release | one command and one revision history for every object | the record is a set of Secrets that can be deleted, and it changes only when Helm runs | write access to Secrets limited to whoever runs Helm, a reinstall or `--take-ownership` to recover, `helm get manifest` with `kubectl diff` to find drift |
| Templates and values | conditionals, loops, one values file per environment | the template language takes time to learn, and charts can be over-templated | flat values, `values.schema.json`, `helm lint`, `helm template`, post-renderers for what the chart leaves out |
| Shared charts | reuse of public and private charts with documented values | a chart creates whatever its templates define | a `helm template` review, Artifact Hub badges and security reports, `--verify`, OCI digests |
| Chart versions | one unchanging version promoted between environments | major upgrades need manual steps, and publishers can version a breaking change as minor or patch | upgrade notes, `pre-upgrade` hooks, `Chart.lock`, a major version for every breaking change |
