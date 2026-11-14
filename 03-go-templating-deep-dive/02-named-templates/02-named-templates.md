# Understanding Named Templates in Helm

## Overview

In this exercise, we’ll use named templates to reduce duplication and improve maintainability in our Kubernetes manifests.
Here’s what we’ll aim to implement:

1. Create a file for named templates under the `templates` folder, conventionally named `_helpers.tpl`.
2. Define named templates for the resource name and the labels.
3. Include them in a Deployment, with the right indentation for each place.
4. Change the labels in one place and see every use update.

## Step-by-Step Guide

Run the commands from this folder. The chart in `go-templating-deep-dive/` is the end state of this exercise.
It continues from exercise 01's chart, so to follow the steps, copy `../01-functions-and-pipelines/go-templating-deep-dive` into an empty directory and edit that copy.

1. **Spot the Duplication:**

   Our Nginx chart from section 02 repeats the same labels in three places in its Deployment, the Deployment's labels, its `spec.selector.matchLabels`, and its Pod template's labels, and once more in the Service's selector.
   The names repeat too: `{{ .Release.Name }}-{{ .Chart.Name }}` in the Deployment and the Service.

   An update that misses one copy breaks the chart quietly. If the Pod labels change but the Service's selector doesn't, the Pods run but receive no traffic.

2. **Bring In a Deployment and Its Values:**

   From your working directory, copy the Nginx chart's Deployment into the chart's `templates/`:

   ```bash
   cp ~/repositories/github/maor-klir/at-the-helm/02-creating-own-helm-charts/08-ide-package-chart/creating-charts/nginx/templates/deployment.yaml go-templating-deep-dive/templates/
   ```

   It reads values the chart doesn't have yet. Replace `values.yaml` with the Nginx chart's settings for the Deployment; `test` and `environment` can go, since `sandbox.yaml` no longer uses them:

   ```yaml
   ## @param replicaCount Number of Nginx replicas to deploy
   replicaCount: 3

   ## Settings for NGINX image
   ##
   ## @param image.name Nginx image name to use
   ## @param image.tag Nginx image tag to use
   image:
     name: nginx
     tag: '1.27.0'

   ## NGINX container ports
   ##
   ## @param containerPorts.http
   containerPorts:
     http: 80
   ```

3. **Create `_helpers.tpl`:**

   Create `templates/_helpers.tpl`. Files whose names start with an underscore aren't rendered as manifests, and their named templates are available to every other template.

   Helm's named templates guide describes the action that creates one: "The `define` action allows us to create a named template inside of a template file."
   A `define` takes the template's name as a string, and ends with `end`, like an `if`.

   Named templates are global, so the name starts with the chart's name.
   The guide gives the reason: "if two templates are declared with the same name the last occurrence will be the one that is used. Since templates in subcharts are compiled together with top-level templates, it is best to name your templates with chart specific names."
   The dots after the chart name are only part of the string, a way to group names.

4. **Define the Full Name:**

   Add a named template for the resource name:

   ```yaml
   {{- define "go-templating-deep-dive.fullname" -}}
   {{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-"  -}}
   {{- end -}}
   ```

   **The name, `fullname`:** the part after the chart prefix is any string; it only has to match the `include` that uses it.
   `fullname` follows the `helm create` scaffold, whose comment above its version says "Create a default fully qualified app name.": the release and the chart together, unique per release.
   The scaffold's other helper, `name`, holds the chart name alone.

   **The dashes:** the helper's output goes straight into lines such as `name: {{ include "go-templating-deep-dive.fullname" . }}`, so it must be exactly the name.
   The newline after the `define` line and the newline before the `end` line are part of the template's body, and the dashes trim them.
   Without any dashes, the `include` returns `"\nmy-app-go-templating-deep-dive\n"`; with them, `"my-app-go-templating-deep-dive"`.

   One dash next to each of those two newlines is enough, so dashes on every action, as here and in the scaffold, are more than the minimum.
   The dashes on the outside, before `define` and after `end`, only trim text around the template, which in `_helpers.tpl` isn't rendered anyway.

   **The expression, read left to right:**

   - `printf "%s-%s" .Release.Name .Chart.Name` builds the raw name.
     `printf` is built into Go template syntax, "An alias for fmt.Sprintf", and each `%s` is replaced by the next argument.
     Writing `{{ .Release.Name }}-{{ .Chart.Name }}` gives the same text, but as two actions, not one value that can be piped.
   - `| trunc 63` cuts the name to 63 characters.
     The pipe passes the name as the last argument, so this runs `trunc 63 "<release>-<chart>"`.
     Most kinds accept names of up to 253 characters, but some need a DNS label, which, as the Kubernetes documentation puts it, may "contain at most 63 characters", as Service names do.
     The helper names every object, so it uses the strictest limit.
   - `| trimSuffix "-"` removes one trailing dash. DNS labels must "end with an alphanumeric character", and `trunc` can stop right after a dash.

   With a 48-character release name, each stage gives:

   | Stage | Result | Length |
   |---|---|---|
   | `printf` | `<release name>-go-templating-deep-dive` | 72 |
   | `trunc 63` | `<release name>-go-templating-` | 63, ends in a dash, so invalid |
   | `trimSuffix "-"` | `<release name>-go-templating` | 62, valid |

   With a short release name such as `my-app`, neither `trunc` nor `trimSuffix` changes anything: the name stays `my-app-go-templating-deep-dive`.
   `trimSuffix "-"` removes only one dash, `"abc--"` becomes `"abc-"`, which would matter only if the cut landed on two dashes in a row.

   The same expression without pipes is nested and reads inside out: `trimSuffix "-" (trunc 63 (printf "%s-%s" .Release.Name .Chart.Name))`.

   Release names themselves are limited to 53 characters, and longer ones are rejected even by `helm template`: `the length must not be longer than 53`.

5. **Include the Full Name:**

   In `templates/deployment.yaml`, replace the name with an `include`:

   ```yaml
   name: {{ include "go-templating-deep-dive.fullname" . }}
   ```

   `include` takes the template's name and a context, the value the dot has inside the template; here, the dot of the Deployment template.

   ```bash
   helm template go-templating-deep-dive -s templates/deployment.yaml
   ```

   The Deployment renders as `name: release-name-go-templating-deep-dive`.

   Go template syntax also has a `template` action, but its output can't be piped to other functions.
   The guide recommends `include`: "It is considered preferable to use `include` over `template` in Helm templates simply so that the output formatting can be handled better for YAML documents."
   Writing `{{ template "go-templating-deep-dive.selectorLabels" . | nindent 4 }}` doesn't pipe the result; the pipe applies to the context argument, and the render fails with `wrong type for value; expected string; got common.Values`.

6. **See What the Context Does:**

   Pass `.Values` as the context instead of the dot:

   ```yaml
   name: {{ include "go-templating-deep-dive.fullname" .Values }}
   ```

   Inside the named template, the dot is now `.Values`, so `.Release.Name` looks for `.Values.Release.Name`, which doesn't exist.
   The render fails inside `_helpers.tpl`, at `<.Release.Name>`, with `nil pointer evaluating interface {}.Name`. Revert the line to pass `.`.

7. **Define and Include the Labels:**

   Add a second named template for the labels:

   ```yaml
   {{- define "go-templating-deep-dive.selectorLabels" -}}
   app: {{ .Chart.Name }}
   release: {{ .Release.Name }}
   {{- end -}}
   ```

   Its output is already YAML, so it needs no `toYaml`, but its indentation is up to us.
   Include it in all three places with `nindent`, at the depth of each block: four spaces under `metadata.labels`, six under `spec.selector.matchLabels`, and eight under the Pod template's `labels`.
   This is the file in `go-templating-deep-dive/templates/deployment.yaml`:

   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: {{ include "go-templating-deep-dive.fullname" . }}
     labels:
       {{- include "go-templating-deep-dive.selectorLabels" . | nindent 4 }}
   spec:
     replicas: {{ .Values.replicaCount }}
     selector:
       matchLabels:
         {{- include "go-templating-deep-dive.selectorLabels" . | nindent 6 }}
     template:
       metadata:
         labels:
           {{- include "go-templating-deep-dive.selectorLabels" . | nindent 8 }}
       spec:
         containers:
           - name: nginx
             image: "{{ .Values.image.name }}:{{ .Values.image.tag }}"
             ports:
               - containerPort: {{ .Values.containerPorts.http }}
   ```

   **Wrong indentation doesn't always fail:** with `nindent 4` in all three places, the render succeeds and `helm lint` passes.
   But the YAML has the wrong structure: `matchLabels` and the Pod template's `labels` are empty, and the labels become keys of `spec.selector` and `spec.template`.
   The API server rejects it: `helm template go-templating-deep-dive -s templates/deployment.yaml | kubectl -n default apply --dry-run=server -f -` reports `strict decoding error: unknown field "spec.selector.app"` and the same for the other labels.

8. **Change the Labels in One Place:**

   Add a `managed-by` label to the `selectorLabels` named template. This is the file in `go-templating-deep-dive/templates/_helpers.tpl`:

   ```yaml
   {{- define "go-templating-deep-dive.fullname" -}}
   {{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-"  -}}
   {{- end -}}

   {{- define "go-templating-deep-dive.selectorLabels" -}}
   app: {{ .Chart.Name }}
   release: {{ .Release.Name }}
   managed-by: "helm"
   {{- end -}}
   ```

   Render again, and `managed-by: "helm"` appears in all three places.

   Selector labels are the one set to keep stable: a Deployment's `spec.selector` can't change after it's created, so changing them for an installed release makes `helm upgrade` fail.
   The `helm create` scaffold keeps two named templates for that reason, a small `selectorLabels` for the selectors, and a `labels` that includes it and adds the rest.
   Helm also adds `app.kubernetes.io/managed-by: Helm` to every object it creates.

9. **Choose Same Line or New Line:**

   The `include` can also sit on the key's line, because `nindent` starts with a new line:

   ```yaml
   labels: {{ include "go-templating-deep-dive.selectorLabels" . | nindent 4 }}
   ```

   The rendered Deployment is the same. Putting the `include` on its own line, starting with `{{-`, is easier to read when lines get long or deeply nested.

## Conclusion

In this exercise, we moved the resource name and the labels into named templates in `_helpers.tpl` and included them where they're needed, with `nindent` matching each block's depth.
Each change now happens in one place, and every object that includes the template stays consistent.
