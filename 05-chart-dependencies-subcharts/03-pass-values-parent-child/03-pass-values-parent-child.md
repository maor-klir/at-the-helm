# Passing values from a parent chart to its subcharts

## Overview

In this exercise, we'll create a small subchart inside config-store's `charts/` directory, and use it to see how the parent chart's values reach a subchart.
Here's a quick summary of the main steps:

1. Create `demo-subchart` with `helm create`, and reduce it to a single ConfigMap.
2. Declare it as a dependency without a repository.
3. Override its value from the parent, first at the top level, then under the subchart's name.
4. See that values under one subchart's name don't reach another subchart.

## Step-by-step guide

The chart in `subcharts/config-store/` is the end state of this exercise, and continues from exercise 02's chart.
To build it yourself, copy exercise 02's `subcharts` directory into an empty directory, and run the steps there.

1. **Create the subchart:**

   ```bash
   cd subcharts/config-store/charts
   helm create demo-subchart
   ```

   Helm 4's scaffold also creates `templates/httproute.yaml`, which goes in the next step together with the other templates.

2. **Reduce it to a ConfigMap:**

   ```bash
   cd demo-subchart/templates
   rm deployment.yaml hpa.yaml httproute.yaml ingress.yaml NOTES.txt service.yaml
   rm -r tests
   mv serviceaccount.yaml configmap.yaml
   ```

   Replace the content of `configmap.yaml`:

   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: {{ include "demo-subchart.fullname" . }}
   data:
     test-value: {{ .Values.customValue }}
   ```

   In `_helpers.tpl`, keep only `demo-subchart.name` and `demo-subchart.fullname`, and replace the content of the subchart's `values.yaml` with a single value:

   ```yaml
   customValue: 'hello from demo-subchart'
   ```

   **The test has to go as well:** the scaffold's `templates/tests/test-connection.yaml` includes `demo-subchart.labels`, which the shortened `_helpers.tpl` no longer defines. If it stays, rendering fails:

   ```text
   Error: config-store/charts/demo-subchart/templates/tests/test-connection.yaml:6:8
     executing "config-store/charts/demo-subchart/templates/tests/test-connection.yaml" at <include "demo-subchart.labels" .>:
       error calling include:
   template: no template "demo-subchart.labels" associated with template "gotpl"
   ```

3. **Declare the subchart:**

   In config-store's `Chart.yaml`, add a second entry, without a `repository`:

   ```yaml
   dependencies:
     - name: postgresql
       version: '16.2.2'
       repository: 'https://charts.bitnami.com/bitnami'
     - name: demo-subchart
       version: '0.1.0'
   ```

   `version` is the one in `demo-subchart/Chart.yaml`. From `config-store/`:

   ```bash
   helm dependency update
   helm dependency list
   ```

   The update downloads PostgreSQL again and prints `Dependency demo-subchart did not declare a repository. Assuming it exists in the charts directory`. It leaves the `demo-subchart/` directory in place, and `Chart.lock` records the new entry with `repository: ""`.

   ```text
   NAME         	VERSION	REPOSITORY                        	STATUS
   postgresql   	16.2.2 	https://charts.bitnami.com/bitnami	ok
   demo-subchart	0.1.0  	                                  	unpacked
   ```

   **The entry is optional for a chart in `charts/`:** without it, `helm template` still renders `demo-subchart`, and `helm dependency list` prints `WARNING: "charts/demo-subchart" is not in Chart.yaml.`
   Declaring it lists it with the other dependencies, and allows the fields that exercise 06 uses, such as `condition`.

   The course prefers to develop each chart in its own directory and reference it with a `file://` repository, so that a subchart doesn't look like part of its parent. This exercise keeps `demo-subchart` in `charts/` for quick tests, and exercise 07 removes it.

4. **Render the subchart's default:**

   ```bash
   helm template . | grep -A6 'demo-subchart/templates/configmap'
   ```

   ```text
   # Source: config-store/charts/demo-subchart/templates/configmap.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: release-name-demo-subchart
   data:
     test-value: hello from demo-subchart
   ```

5. **Set the value at the parent's top level:**

   Add to the end of config-store's `values.yaml`:

   ```yaml
   customValue: 'hello from config-store'
   ```

   The render still shows `test-value: hello from demo-subchart`. A top-level key in the parent's values belongs to the parent's own templates.

6. **Nest the value under the subchart's name:**

   Move the key under `demo-subchart`:

   ```yaml
   demo-subchart:
     customValue: 'hello from config-store'
   ```

   The render now shows `test-value: hello from config-store`, and the subchart's template still reads `.Values.customValue`.
   The Subcharts and Global Values guide, with its example subchart `mysubchart`: *"Any directives inside of the `mysubchart` section will be sent to the `mysubchart` chart."*

   A subchart can't know the name of the chart that includes it, so it never reads `.Values.config-store.…`. The `postgresql:` block from exercise 02 works the same way.

7. **Check that values stay with their subchart:**

   Under `postgresql:` in config-store's `values.yaml`, add `fullnameOverride: my-new-name`, and in `demo-subchart/templates/configmap.yaml` add a line that reads the same key:

   ```yaml
     test-value2: {{ .Values.fullnameOverride }}
   ```

   ```bash
   helm template . | grep -E '^  name: |test-value'
   ```

   The PostgreSQL objects are now named `my-new-name` and `my-new-name-hl`, but the ConfigMap shows `test-value2:` with nothing after it. `postgresql.fullnameOverride` reaches only the `postgresql` chart.
   The line renders no value at all, which YAML reads as null, not as an empty string.

   Remove `fullnameOverride` from `postgresql:` again, and keep the `test-value2` line. Global values, which every chart can read, are exercise 04's topic.

   **Change a packaged dependency only through values:** the PostgreSQL chart is the archive in `charts/`, and `helm dependency update` replaces it with the downloaded one, so edits inside it wouldn't last.

## Conclusion

In this exercise, we created `demo-subchart` inside config-store's `charts/` directory, declared it without a repository, and passed it a value under its own name in the parent's `values.yaml`.
Exercise 04 sets global values, which the parent and every subchart can read.
