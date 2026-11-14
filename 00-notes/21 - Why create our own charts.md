#helm #kubernetes

# Why create our own charts

The charts we have installed so far, such as `bitnami/wordpress`, are written, versioned, and published by someone else.
A chart is a set of files we can also write ourselves.
The Charts documentation describes the format: *"Charts are created as files laid out in a particular directory tree. They can be packaged into versioned archives to be deployed."*

The sections below cover six reasons to write a chart of our own, and the Helm feature each one relies on.
A chart of our own also brings the costs described in **02 - Benefits and limitations of Helm**, such as the learning curve and over-templating, so a few manifests that rarely change may not need one.

## No published chart fits our application

**An in-house application has no published chart:** Artifact Hub and `helm search hub` list public charts (see **11 - Exploring charts and releases with the Helm CLI**), and an application our own team develops is in neither.
The same applies to a public application whose setup or dependencies differ from what its published charts assume.

**A published chart follows its publisher's decisions:** which images it references, which values it exposes, and how long each version line receives fixes.
A publisher can also retire a chart with the `deprecated` field in `Chart.yaml`: *"If the **latest** version of a chart in the repository is marked as deprecated, then the chart as a whole is considered to be deprecated."*

**Bitnami's image move is one example:** the image tags that WordPress charts 23.1.20 and 23.1.28 render no longer exist under `docker.io/bitnami`.
Bitnami's README points to where they went: *"If you are looking for our previous generation of images based on Debian Linux, please see the Bitnami Legacy registry."*
Its last images were pushed in August 2025, so they receive no security updates.

The current WordPress charts, 34.x, render `bitnami/wordpress:latest`, the only tag left in that repository.
Helm's best practices advise against that: *"A container image should use a fixed tag or the SHA of the image. It should not use the tags `latest`, `head`, `canary`, or other tags that are designed to be "floating"."*
In a chart of our own, we decide which images and tags it references.

## A configuration interface designed for our application

A published chart can be changed only through the values its templates read (see **03 - Helm vs. Kustomize**).
To serve many users, a general-purpose chart exposes many values: the computed values of our WordPress 23.1.20 release are 794 lines long (see **11 - Exploring charts and releases with the Helm CLI**).

Our own chart's `values.yaml` holds what changes between our installations, such as the image tag, replica count, host names, and resource limits, with defaults that match our environments.
The best practices ask chart authors to plan for how values are overridden: *"When designing the structure of your values, keep in mind that users of your chart may want to override them via either the `-f` flag or with the `--set` option."*

A post-renderer can change fields a published chart doesn't expose, without a chart of our own (see **02 - Benefits and limitations of Helm**).
It patches the rendered manifests at every install and upgrade, while our own chart puts those fields into its templates and values.

## Control over every object and the logic in the templates

The chart template guide describes what happens to the files in `templates/`:

> *"When Helm evaluates a chart, it will send all of the files in the `templates/` directory through the template rendering engine. It then collects the results of those templates and sends them on to Kubernetes."*

Every object our application needs is a file we write there, including objects a published chart leaves out, such as a NetworkPolicy or a PodDisruptionBudget.
Each field gets the value or default we choose.

**Templates also hold logic:** conditionals and loops decide which objects and fields are rendered (see **02 - Benefits and limitations of Helm** and **24 - Values and release information in a chart**), and functions can stop a render whose values would produce a broken release.

The chart development tips describe `required`: *"The `required` function gives developers the ability to declare a value entry as required for template rendering. If the entry is empty in `values.yaml`, the template will not render and will return an error message supplied by the developer."*

In the `helm create` scaffold's Deployment, replacing the default image tag with `required` makes the tag mandatory:

```yaml
image: "{{ .Values.image.repository }}:{{ .Values.image.tag | required "image.tag is required" }}"
```

The scaffold's `image.tag` is empty, so `helm template` stops with our message, and `helm install` and `helm upgrade` stop the same way before sending anything to the cluster:

```text
Error: execution error at (app-chart/templates/deployment.yaml:41:72): image.tag is required
```

`fail` covers checks that need a condition first: it *"Unconditionally returns an empty `string` and an `error` with the specified text."*

## One version for the application and its objects

In a chart of our own, we set both version fields in `Chart.yaml` (see **01 - The role of Helm in Kubernetes**).
`version` is the chart's version, which `helm package` puts into the archive name, and `appVersion` is the version of the application the chart deploys.

The `helm create` scaffold connects the two: its Deployment falls back to `appVersion` as the image tag.

```yaml
image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
```

With the scaffold's `appVersion: "1.16.0"` and no `image.tag`, the image renders as `nginx:1.16.0`.

**A new application version becomes a new chart version:** `helm package` can set both fields when it builds the archive, with `--version` to *"set the version on the chart to this semver version"* and `--app-version` to *"set the appVersion on the chart to this version"*.
The image tag, the ConfigMaps, and every other object then change together under one chart version.

**Upgrades and rollbacks follow the chart version:** `helm history` lists the chart and app version of every revision, and `helm rollback` returns all of the release's objects to an earlier revision (see **15 - Rolling back releases**).

## Organization-wide standards

A chart maintained inside an organization can carry the organization's rules, such as standard labels, pinned images, resource requests, and security contexts.
Helm's best practices allow for this:

> *"We focus primarily on best practices for charts that may be publicly deployed. We know that many charts are for internal-use only, and authors of such charts may find that their internal interests override our suggestions here."*

**Standard labels:** *"Helm itself never requires that a particular label be present."*
The best practices recommend four on every chart: `app.kubernetes.io/name`, `helm.sh/chart`, `app.kubernetes.io/managed-by`, and `app.kubernetes.io/instance`.
The `helm create` scaffold renders all four, plus the optional `app.kubernetes.io/version`, from named templates in `templates/_helpers.tpl`.

**Shared definitions in a library chart:** the Library Charts documentation describes the type:

> *"A library chart is a type of Helm chart that defines chart primitives or definitions which can be shared by Helm templates in other charts. This allows users to share snippets of code that can be re-used across charts, avoiding repetition and keeping charts DRY."*

A chart with `type: library` in `Chart.yaml` cannot be installed: `helm install` stops with `library charts are not installable`.
Application charts list it as a dependency and include its named templates, so a label or security context defined once in the library reaches every chart that updates to the new library version.

**Checks on the values and the cluster:** `values.schema.json` rejects values that don't match the chart's schema (see **02 - Benefits and limitations of Helm**), and `required` and `fail` stop a render from inside the templates.
`kubeVersion` in `Chart.yaml` limits the Kubernetes versions a chart installs on: *"Helm will validate the version constraints when installing the chart and fail if the cluster runs an unsupported Kubernetes version."*

## Reusing existing charts as dependencies

A chart of our own doesn't have to define every object itself.
The Charts documentation says *"In Helm, one chart may depend on any number of other charts."*
An application chart can add a database, a cache, or a library chart, from the community or from a private repository.

Dependencies are listed in `Chart.yaml`.
For a chart in an OCI registry, *"The `repository` for a given entry in `Chart.yaml` is specified as the registry reference without the basename"*:

```yaml
dependencies:
  - name: postgresql
    version: ~16.2.2
    repository: oci://registry-1.docker.io/bitnamicharts
    condition: postgresql.enabled
```

`helm dependency update` resolves the range and downloads the chart into `charts/`.
On Helm 4.3.1 this entry resolves to `postgresql-16.2.5.tgz`, and `Chart.lock` records `16.2.5` (see **02 - Benefits and limitations of Helm**).
The best practices suggest such patch-level ranges, and a condition for every optional dependency: *"Conditions or tags should be added to any dependencies that _are optional_."*

**A dependency can also come from our own repository:** the Chart Repository Guide defines one: *"A _chart repository_ is an HTTP server that houses an `index.yaml` file and optionally some packaged charts."*
The same guide suggests an alternative: *"If you are considering creating a chart repository, you may want to consider using an OCI registry instead."*
Either one also hosts the charts we write, so other teams can install them or depend on them.

## Reasons and the Helm features they rely on

| Reason | What our own chart uses |
|---|---|
| No published chart fits | a chart directory of our own, published to our chart repository or OCI registry |
| Configuration for our application | a `values.yaml` with the values our installations change |
| Control over objects and logic | templates with conditionals, loops, `required`, and `fail` |
| One version for the application | `version` and `appVersion` in `Chart.yaml`, set by `helm package` |
| Organization-wide standards | standard labels, library charts, `values.schema.json`, `kubeVersion` |
| Reuse of existing charts | `dependencies` in `Chart.yaml`, `helm dependency update`, `Chart.lock` |
