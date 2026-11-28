#helm #templating #libraries

# Library charts

A library chart holds named templates that other charts include, and deploys nothing itself.
The library charts documentation: *"A library chart is a type of Helm chart that defines chart primitives or definitions which can be shared by Helm templates in other charts."*

The examples below use two charts: `parent-chart`, an application chart created with `helm create`, and `common`, a library chart in `parent-chart`'s `charts/` directory.
The scaffold's `name` and `fullname` helpers moved from `parent-chart` into `common`, renamed `common.name` and `common.fullname`.

## What makes a chart a library chart

`type: library` in `Chart.yaml`.
The documentation lists what the type brings:

| Feature in the documentation | Seen in practice |
|---|---|
| *"Logic to prevent installation of a common chart"* | `helm install` and `helm template` of `common` both fail with `library charts are not installable` |
| *"No rendering of templates in a common chart which may contain release artifacts"* | a ConfigMap template added to `common/templates/` rendered nothing in the parent's output |
| *"Allow for dependent charts to use the importer's context"* | `common.fullname`, included from `parent-chart`, used `parent-chart`'s name and values |

A library chart's templates are therefore named templates, in files whose names start with `_`, such as `_naming.tpl`.
Bitnami's charts share theirs the same way: WordPress and PostgreSQL both depend on Bitnami's `common` library chart.
A library chart is published like any other chart: `common` 2.41.0, with `type: library`, is in both Bitnami's OCI registry and its HTTP repository.

## Using a library chart

The application chart declares the library chart like any dependency, and `helm dependency update` copies it into `charts/` as an archive:

```yaml
dependencies:
  - name: common
    version: 0.1.0
    repository: 'file://./charts/common'
```

**A library chart inside `charts/` ends up there twice:** next to `charts/common/`, the update wrote `charts/common-0.1.0.tgz`, and Helm loaded both.
An edit in `charts/common/` rendered without another update.
The documentation's example keeps the library chart outside the application chart, `repository: file://../mylibchart`, so the archive is the only copy inside it.

**Moving a helper renames it:** in the library chart, `parent-chart.fullname` became `common.fullname`, and `parent-chart.name` became `common.name`.
Every `include` of the old names, in `parent-chart`'s templates and in its `_helpers.tpl`, has to use the new ones.

Until it does, the render fails with `template: no template "parent-chart.name" associated with template "gotpl"`, and Helm prints the chain of includes that led to the old name.

**Template names are shared by all charts in a render:** `common` is the usual name for library charts like this, so two of them can define the same template name, and only one definition is used (see **32 - Named templates**).
Each template's name starts with its library chart's name, as in `common.fullname`, to make that less likely.

## The context a library chart's templates run with

A library chart brings no context of its own to the render.
Its templates run with whatever the including template passes as the second argument of `include`.
`parent-chart`'s templates pass `.`, their top-level object, which holds `parent-chart`'s `.Chart`, `.Release`, and `.Values`:

```yaml
# parent-chart/templates/service.yaml
metadata:
  name: {{ include "common.fullname" . }}
```

```yaml
# common/templates/_naming.tpl, inside "common.name"
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
```

**The library chart's helpers read the parent's chart and values:** inside them, `.Chart.Name` is `parent-chart`, so the Service is named `release-name-parent-chart`.
With `--set nameOverride=web`, they read `parent-chart`'s `nameOverride`: the Service became `release-name-web`, with the label `app.kubernetes.io/name: web`.

A named template that a parent includes from an application subchart works the same way (see **32 - Named templates**).

**The library chart's own `values.yaml` isn't part of that context:** Helm puts a dependency's values under the dependency's name in the parent's values.
With `libValue: set-in-library` in `common/values.yaml`, `.Values.libValue` was empty inside a helper called with `parent-chart`'s `.`, and the value was at `.Values.common.libValue`.

A library chart's helper that needs a default sets it in the template, as `common.name` does with `default .Chart.Name`.

## Beyond helpers

A library chart can also define whole objects for applications to complete.
The documentation's example defines a ConfigMap in the library chart, and a merge helper that combines it with the application's own `data`: *"This is important when a chart wants to use common code that it needs to customize with its configuration."*

## Verify

From `06-advanced-topics/08-library-charts`, the parent's objects take their names from the parent, and the library chart alone can't be rendered:

```bash
helm template library-charts/parent-chart | grep -E '^kind|^  name:|helm.sh/chart' | sort -u
helm template x library-charts/parent-chart/charts/common
```

```text
        helm.sh/chart: parent-chart-0.1.0
    helm.sh/chart: parent-chart-0.1.0
kind: Deployment
kind: Service
  name: release-name-parent-chart
Error: library charts are not installable
```
