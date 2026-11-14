# Creating Charts with `helm create`

## Overview

In this exercise, we'll use the `helm create` command to generate a chart's files instead of writing each one by hand.
The generated chart uses Go template features that the Go templating section covers in depth, so don't worry if some of it isn't clear yet.

Here's a summary of the main steps:

1. Read the help for `helm create`.
2. Create a chart with `helm create backend-app`.
3. Explore the generated `Chart.yaml`, `values.yaml`, and `templates/`.
4. See how the templates share names and labels through `_helpers.tpl`.
5. Render and lint the generated chart.

## Step-by-Step Guide

Run the commands in an empty directory, so the new chart doesn't end up inside this repository.
The steps describe what `helm create` generates today, checked with Helm 4.3.2; `creating-charts/backend-app/` in this folder is the older scaffold generated for the lecture.

1. **Read the Help:**

   ```bash
   helm create --help
   ```

   The help describes the command: "This command creates a chart directory along with the common files and directories used in a chart."
   It takes the path of the new chart directory as its argument.

   The help also lists `--starter` (`-p`), which generates the chart from your own template chart instead of the built-in scaffold: "The `helm create` command takes an optional `--starter` option that lets you specify a "starter chart"."
   An organization can keep its standard labels, security settings, and file layout in a starter chart.

2. **Create the Chart:**

   ```bash
   cd "$(mktemp -d)"
   helm create backend-app
   find backend-app | sort
   ```

   Helm prints `Creating backend-app` and generates this tree:

   ```text
   backend-app
   backend-app/charts
   backend-app/Chart.yaml
   backend-app/.helmignore
   backend-app/templates
   backend-app/templates/deployment.yaml
   backend-app/templates/_helpers.tpl
   backend-app/templates/hpa.yaml
   backend-app/templates/httproute.yaml
   backend-app/templates/ingress.yaml
   backend-app/templates/NOTES.txt
   backend-app/templates/serviceaccount.yaml
   backend-app/templates/service.yaml
   backend-app/templates/tests
   backend-app/templates/tests/test-connection.yaml
   backend-app/values.yaml
   ```

   The directory name becomes the chart's name: `Chart.yaml` says `name: backend-app`, and every named template in `_helpers.tpl` starts with `backend-app.`.
   `charts/` starts empty; it holds the chart's dependencies once it has some.

3. **Explore `Chart.yaml` and `values.yaml`:**

   `Chart.yaml` holds six fields, each explained by a comment above it:

   ```yaml
   apiVersion: v2
   name: backend-app
   description: A Helm chart for Kubernetes
   type: application
   version: 0.1.0
   appVersion: "1.16.0"
   ```

   `values.yaml` holds documented defaults for everything the templates configure: the image, the ServiceAccount, the Service, Ingress, HTTPRoute, resources, probes, autoscaling, volumes, and scheduling.
   `image.tag` is empty, so the Deployment falls back to `appVersion` and runs `nginx:1.16.0`.

4. **Explore the Templates:**

   Each Kubernetes object has its own template, and the templates share names and labels through the named templates defined in `_helpers.tpl`: `backend-app.name`, `backend-app.fullname`, `backend-app.chart`, `backend-app.labels`, `backend-app.selectorLabels`, and `backend-app.serviceAccountName`.
   `templates/deployment.yaml` uses them with `include`:

   ```yaml
   metadata:
     name: {{ include "backend-app.fullname" . }}
     labels:
       {{- include "backend-app.labels" . | nindent 4 }}
   spec:
     {{- if not .Values.autoscaling.enabled }}
     replicas: {{ .Values.replicaCount }}
     {{- end }}
     selector:
       matchLabels:
         {{- include "backend-app.selectorLabels" . | nindent 6 }}
   ```

   Prefixing the named templates with the chart name follows Helm's best practices, which recommend the command for exactly that: "It is highly recommended that new charts are created via `helm create` command as the template names are automatically defined as per this best practice."
   Optional sections are wrapped in `with` blocks, such as `{{- with .Values.resources }}`, so they're rendered only when the value is set.
   `include`, `nindent`, and `with` are covered in the Go templating section.

   For traffic from outside the cluster, the scaffold offers two templates, both off by default: `ingress.yaml` for an Ingress, and `httproute.yaml` for an HTTPRoute from the Gateway API.
   Ingress is stable and still widely used, and most public charts expose it; the Kubernetes documentation notes that its API is frozen and recommends Gateway: "The Kubernetes project recommends using Gateway instead of Ingress. The Ingress API has been frozen."
   Which one to enable depends on the controller the cluster runs, set with `ingress.enabled` or `httpRoute.enabled`, and `templates/NOTES.txt` prints how to reach the application through whichever is enabled.

5. **Render and Lint the Chart:**

   ```bash
   helm template my-app backend-app
   helm lint backend-app
   ```

   With the default values, the chart renders four objects: a ServiceAccount, a Service, a Deployment, and the test Pod from `templates/tests/`.
   The Ingress, the HTTPRoute, and the HorizontalPodAutoscaler stay out, because their `enabled` values default to `false`.
   `helm lint` reports only `[INFO] Chart.yaml: icon is recommended`.

## Conclusion

In this exercise, we generated a chart with `helm create` and explored its files.
The scaffold is a good starting point for new charts, and after the Go templating section, every part of it will make sense.
