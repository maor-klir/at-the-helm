# Creating a library chart

## Overview

In this exercise, we'll create a library chart, `common`, inside the `charts/` directory of an application chart, `parent-chart`, move the chart's name helpers into it, and use them from the parent.
Here's a quick summary of the main steps:

1. Create both charts, and turn `common` into a library chart.
2. Move the `name` and `fullname` helpers into `common`.
3. Declare `common` as a dependency of `parent-chart`.
4. Fix the parent's references to the moved helpers, and render it.

## Step-by-step guide

The chart in `library-charts/parent-chart/`, with `common` in its `charts/` directory, is the end state of this exercise. To build it yourself, run the steps in an empty directory.

1. **Create both charts:**

   ```bash
   mkdir library-charts
   cd library-charts
   helm create parent-chart
   cd parent-chart/charts
   helm create common
   ```

   `common` is the usual name for a library chart of shared helpers; Bitnami's charts, WordPress among them, depend on Bitnami's own `common` library chart. Since so many charts use the name, two dependencies called `common` can clash.

   A library chart could also be published in a repository; only its `repository` in the parent's `Chart.yaml` would differ.

2. **Turn `common` into a library chart:**

   In `common/`, delete the `charts/` directory, everything inside `templates/`, and `values.yaml`. In `common/Chart.yaml`, change the type and the description:

   ```yaml
   description: A set of common utilities for our charts.
   type: library
   ```

   The library charts documentation lists what the type provides, among them *"Logic to prevent installation of a common chart"* and *"No rendering of templates in a common chart which may contain release artifacts"*:

   ```bash
   helm template x common
   ```

   ```text
   Error: library charts are not installable
   ```

3. **Move the name helpers into the library chart:**

   Move the `name` and `fullname` helpers, with their comments, from `parent-chart/templates/_helpers.tpl` to a new file, `common/templates/_naming.tpl`, and rename them to `common.name` and `common.fullname`:

   ```yaml
   {{- define "common.name" -}}
   {{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
   {{- end }}
   ```

   ```yaml
   {{- define "common.fullname" -}}
   {{- if .Values.fullnameOverride }}
   ```

   The rest of `fullname` stays as `helm create` wrote it. A library chart's templates are named templates in files that start with `_`, which Helm doesn't render as manifests.

4. **Trim the parent chart:**

   To keep the changes small, delete `templates/tests/`, `hpa.yaml`, `ingress.yaml`, `serviceaccount.yaml`, and `NOTES.txt` from `parent-chart/templates/`, and with Helm 4's scaffold also `httproute.yaml`. `deployment.yaml`, `service.yaml`, and `_helpers.tpl` remain.

5. **Declare the dependency:**

   In `parent-chart/Chart.yaml`:

   ```yaml
   dependencies:
     - name: common
       version: 0.1.0
       repository: 'file://./charts/common'
   ```

   From `library-charts/`:

   ```bash
   helm dependency update parent-chart
   helm dependency list parent-chart
   ```

   ```text
   NAME  	VERSION	REPOSITORY            	STATUS
   common	0.1.0  	file://./charts/common	ok
   ```

   The update packs the library chart into `charts/common-0.1.0.tgz`, next to its directory, and writes `Chart.lock`.

   **The chart now holds `common` twice:** Helm loads both copies, and in a test, an edit in `charts/common/` rendered without another `helm dependency update`. The library charts documentation keeps the library chart next to the application chart instead, with `repository: file://../mylibchart`, so the archive is the only copy inside the parent.

6. **Fix the references:**

   ```bash
   helm template parent-chart
   ```

   ```text
   Error: parent-chart/templates/service.yaml:4:11
     executing "parent-chart/templates/service.yaml" at <include "parent-chart.fullname" .>:
       error calling include:
   ```

   Replace `parent-chart.fullname` with `common.fullname` in `service.yaml` and `deployment.yaml`, and render again. The next error goes through the labels helpers, and Helm prints the whole chain:

   ```text
   Error: parent-chart/templates/service.yaml:6:8
     executing "parent-chart/templates/service.yaml" at <include "parent-chart.labels" .>:
       error calling include:
   parent-chart/templates/_helpers.tpl:13:3
     executing "parent-chart.labels" at <include "parent-chart.selectorLabels" .>:
       error calling include:
   parent-chart/templates/_helpers.tpl:24:27
     executing "parent-chart.selectorLabels" at <include "parent-chart.name" .>:
       error calling include:
   template: no template "parent-chart.name" associated with template "gotpl"
   ```

   In `_helpers.tpl`, replace `parent-chart.name` with `common.name` on line 24, and `parent-chart.fullname` with `common.fullname` on line 33, in the `serviceAccountName` helper.

7. **Render the chart:**

   ```bash
   helm template parent-chart | grep -E '^kind|^  name:|app.kubernetes.io/name'
   ```

   ```text
   kind: Service
     name: release-name-parent-chart
       app.kubernetes.io/name: parent-chart
       app.kubernetes.io/name: parent-chart
   kind: Deployment
     name: release-name-parent-chart
       app.kubernetes.io/name: parent-chart
         app.kubernetes.io/name: parent-chart
           app.kubernetes.io/name: parent-chart
   ```

   The helpers live in `common`, yet `.Chart.Name` is `parent-chart`: `include "common.fullname" .` passes the parent's context, the same way as when a parent includes an application subchart's template.
   The documentation names this among the features of the `library` type: *"Allow for dependent charts to use the importer's context"*. The parent needs no `common:` section in its values for that.

   A library chart may still have a `values.yaml`: a test value in one appeared in the parent's values under `.Values.common`, like any dependency's, while `common.fullname` kept reading the parent's `.Values.nameOverride`.

8. **Know the chart's gap:**

   `values.yaml` still sets `serviceAccount.create: true`, but `serviceaccount.yaml` is gone. The Deployment refers to a ServiceAccount the chart no longer creates:

   ```text
         serviceAccountName: release-name-parent-chart
   ```

   `helm template` and `helm lint` don't notice, and neither does the install:

   ```bash
   helm -n library-charts install demo library-charts/parent-chart --create-namespace
   kubectl -n library-charts get deployment,pods
   kubectl -n library-charts get events --field-selector involvedObject.kind=ReplicaSet
   ```

   Helm reports `STATUS: deployed`, but the Deployment stays at `0/1` with no Pods. Its ReplicaSet can't create them:

   ```text
   Error creating: pods "demo-parent-chart-5955557f55-" is forbidden: error looking up service account library-charts/demo-parent-chart: serviceaccount "demo-parent-chart" not found
   ```

   An upgrade with `--set serviceAccount.create=false` renders `serviceAccountName: default`, and the Pod starts with the namespace's `default` ServiceAccount. Delete the namespace afterwards:

   ```bash
   helm -n library-charts upgrade demo library-charts/parent-chart --set serviceAccount.create=false
   kubectl delete namespace library-charts
   ```

## Conclusion

In this exercise, we created a library chart, moved the name helpers into it, and saw that its helpers run with the context of the chart that includes them.
Exercise 09 starts the chart tests part of the section.
