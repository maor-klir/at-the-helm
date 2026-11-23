# Using `if` and `else` in Helm templates

## Overview

In this exercise, we'll revisit `if` and `else` in Helm templates: to render a whole object, part of one, or a single value depending on the values.
Here's a brief summary of what we'll implement:

1. Add the nginx chart's service settings to `values.yaml`.
2. Add a Service template that uses the named templates for its name, labels, and selector.
3. Render the container port only when the Service is enabled.
4. Choose the replica count inline with `if` and `else`, and keep the output free of extra spaces.
5. Chain more than two cases with `else if`.

## Step-by-step guide

Run the commands from this folder. The chart in `go-templating-deep-dive/` is the end state of this exercise.
It continues from exercise 02's chart, so to follow the steps, copy `../02-named-templates/go-templating-deep-dive` into an empty directory and edit that copy.

1. **Add the Service values:**

   Add the nginx chart's service settings to `values.yaml`, after `containerPorts`:

   ```yaml
   ## Settings for nginx Service
   ##
   ## @param service.enabled Whether to deploy the Service altogether or not
   ## @param service.type The type of Service in front of the nginx Pods
   ## @param service.port The port where the Service is receiving requests
   service:
     enabled: true
     type: ClusterIP
     port: 80
   ```

2. **Add the Service template:**

   From your working directory, copy the nginx chart's Service into `templates/`, where `<repo>` is your clone of this repository:

   ```bash
   cp <repo>/02-creating-your-own-helm-charts/08-ide-package-chart/creating-charts/nginx/templates/service.yaml go-templating-deep-dive/templates/
   ```

   Replace its hardcoded name, labels, and selector with the named templates from exercise 02.
   Both label blocks sit four spaces deep, so both use `nindent 4`. This is the file in `go-templating-deep-dive/templates/service.yaml`:

   ```yaml
   {{- if .Values.service.enabled }}
   apiVersion: v1
   kind: Service
   metadata:
     name: {{ include "go-templating-deep-dive.fullname" . }}
     labels:
       {{- include "go-templating-deep-dive.selectorLabels" . | nindent 4 }}
   spec:
     type: {{ .Values.service.type }}
     selector:
       {{- include "go-templating-deep-dive.selectorLabels" . | nindent 4 }}
     ports:
       - protocol: TCP
         port: {{ .Values.service.port }}
         targetPort: {{ .Values.containerPorts.http }}
   {{ end }}
   ```

   The Service and the Deployment now share the same name, `release-name-go-templating-deep-dive`. Names only have to be unique within a kind, so that's allowed.

   ```bash
   helm template go-templating-deep-dive
   ```

   The Service renders first, then the Deployment, and the Service's labels and selector match the Deployment's Pod labels.

3. **Render part of an object conditionally:**

   An `if` can wrap a few lines inside a template as well as a whole object.
   In `templates/deployment.yaml`, render the container's `ports` only when the Service is enabled:

   ```yaml
   containers:
     - name: nginx
       image: "{{ .Values.image.name }}:{{ .Values.image.tag }}"
       {{- if .Values.service.enabled }}
       ports:
         - containerPort: {{ .Values.containerPorts.http }}
       {{- end }}
   ```

   Set `service.enabled: false` in `values.yaml` and render again: the Service is gone, and the container has no `ports`.
   The chart in this folder keeps `enabled: false`; `helm template go-templating-deep-dive --set service.enabled=true` renders both again.

4. **Choose a value inline:**

   An `if` and `else` can also produce a single value on one line.
   As a temporary experiment, choose the replica count from an `environment` value instead of `replicaCount`:

   ```yaml
   replicas: {{ if eq .Values.environment "production" }} 5 {{ else }} 2 {{ end }}
   ```

   ```bash
   helm template go-templating-deep-dive -s templates/deployment.yaml --set environment=production
   ```

   The output is valid YAML, but with extra spaces: the spaces inside the branches are plain text, so the line renders as `replicas:··5·`, with `·` marking each space.

   Dashes on the inner side of the actions trim them:

   ```yaml
   replicas: {{ if eq .Values.environment "production" -}} 5 {{- else -}} 2 {{- end }}
   ```

   Now the line renders as `replicas: 5`, and with `--set environment=staging`, or no `environment` at all, as `replicas: 2`.

   For a choice between two values, the Sprig `ternary` function is shorter.
   The function list describes it: "The `ternary` function takes two values, and a test value. If the test value is true, the first value will be returned. If the test value is empty, the second value will be returned."

   ```yaml
   replicas: {{ ternary 5 2 (eq .Values.environment "production") }}
   ```

   Revert the line to `replicas: {{ .Values.replicaCount }}` when you're done.

5. **Chain conditions with `else if`:**

   More than two cases chain with `else if`, closed by a single `end`:

   ```yaml
   replicas: {{ if eq .Values.environment "production" }}5{{ else if eq .Values.environment "staging" }}3{{ else }}2{{ end }}
   ```

   With `--set environment=staging`, this renders `replicas: 3`.

## Conclusion

In this exercise, we used `if` to render a whole object, part of one, and a single value, and trimmed the whitespace an inline `if` leaves around its value.
Conditionals add cognitive load: every one is another case to keep in mind when reading what a template renders, so use them where a value really varies.
