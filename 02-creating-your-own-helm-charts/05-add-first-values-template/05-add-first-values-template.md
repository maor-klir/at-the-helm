# Adding the First Values to the Nginx Chart

## Overview

In this exercise, we're going to make our chart more flexible by defining values in the `values.yaml` file and using them in the templates.
The goal is to allow users to set the replica count, the image name and tag, the container port, and the service type and port.

Here's a quick summary of the main steps:

1. Define `replicaCount`, `image.name` and `image.tag`, `containerPorts.http`, and `service.type` and `service.port` in `values.yaml`.
2. Document each value.
3. Use the values in `deployment.yaml` and `service.yaml`.
4. Render and lint the chart to confirm the output.

## Step-by-Step Guide

Run the commands from this folder. The chart in `creating-charts/nginx/` is the end state of this exercise.
It continues from exercise 01's chart, so to follow the steps, copy `../01-creating-first-helm-chart/creating-charts` into an empty directory and edit that copy.

1. **Make the Replica Count Configurable:**

   In `values.yaml`, add the replica count with a comment that documents it:

   ```yaml
   ## @param replicaCount Number of Nginx replicas to deploy
   replicaCount: 1
   ```

   In `templates/deployment.yaml`, replace the hardcoded `replicas: 1` with the value:

   ```yaml
   replicas: {{ .Values.replicaCount }}
   ```

   `helm template creating-charts/nginx` renders `replicas: 1`. Change the value to `3` and render again to get `replicas: 3`, which is what the chart in this folder uses.

2. **Make the Image Configurable:**

   Group the image name and tag under `image`:

   ```yaml
   ## Settings for NGINX image
   ##
   ## @param image.name Nginx image name to use
   ## @param image.tag Nginx image tag to use
   image:
     name: nginx
     tag: '1.27.0'
   ```

   In `templates/deployment.yaml`, build the image from both values:

   ```yaml
   image: "{{ .Values.image.name }}:{{ .Values.image.tag }}"
   ```

   The tag is quoted so YAML reads it as a string, which Helm's best practices sum up as "quote all strings".
   Unquoted, `1.27.0` happens to stay a string, but `1.10` becomes the number 1.1 and renders as `nginx:1.1`.

   The `quote` function adds quotes in the template instead: `{{ .Values.image.tag | quote }}` renders `"1.27.0"`.
   It can't repair a value YAML has already converted, though: with an unquoted `tag: 1.10`, it renders `"1.1"`.
   Without `quote`, a string value can also change type in the rendered manifest: a value of `"true"` renders as the bare `true`, which YAML reads as a boolean.

   Helm's chart tips give the rule: "When you are working with string data, you are always safer quoting the strings than leaving them as bare words", "But when working with integers do not quote the values."
   That's why `replicaCount` and the ports stay unquoted in the templates: `{{ .Values.containerPorts.http | quote }}` would render `"80"`, a string where Kubernetes expects a number.

   Grouping the settings under `image` is a choice: flat keys such as `imageName` and `imageTag` work as well.
   The `helm create` scaffold groups them too, as `image.repository` and `image.tag`.

3. **Make the Service Configurable:**

   Add the service settings:

   ```yaml
   ## Settings for NGINX service
   ##
   ## @param service.type The type of service in front of the Nginx pods
   ## @param service.port The port where the service is receiving requests
   service:
     type: ClusterIP
     port: 80
   ```

   In `templates/service.yaml`, replace the hardcoded type and port:

   ```yaml
   type: {{ .Values.service.type }}
   ```

   ```yaml
   port: {{ .Values.service.port }}
   ```

4. **Add the Container Port:**

   The Service's `targetPort` has to match the port Nginx listens on in the container, not the Service's own port.
   `kubectl explain` defines the two fields: `port` is "The port that will be exposed by this service.", and `targetPort` is the "Number or name of the port to access on the pods targeted by the service."

   Add the container port as its own value, above the service settings:

   ```yaml
   ## NGINX container ports
   ##
   ## @param containerPorts.http
   containerPorts:
     http: 80
   ```

   Use it in both templates, as the container port in `templates/deployment.yaml` and as the target port in `templates/service.yaml`:

   ```yaml
   - containerPort: {{ .Values.containerPorts.http }}
   ```

   ```yaml
   targetPort: {{ .Values.containerPorts.http }}
   ```

   One value now sets both fields, so they can't drift apart: `helm template creating-charts/nginx --set containerPorts.http=8080` renders `containerPort: 8080` and `targetPort: 8080`, while `port` stays 80.

5. **Document the Values:**

   Helm's best practices ask for every value to be documented: "Every defined property in `values.yaml` should be documented. The documentation string should begin with the name of the property that it describes, and then give at least a one-sentence description."

   The `## @param <key> <description>` comments follow the format of Bitnami's readme-generator-for-helm, which builds a chart README's parameter table from them: "For a parameter: `## @param fullKeyPath [modifier?] Description`."
   The `@param containerPorts.http` line has no description yet; something like `HTTP port the Nginx container listens on` would complete it.

   The complete `values.yaml`, as in `creating-charts/nginx/values.yaml`:

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

   ## Settings for NGINX service
   ##
   ## @param service.type The type of service in front of the Nginx pods
   ## @param service.port The port where the service is receiving requests
   service:
     type: ClusterIP
     port: 80
   ```

6. **Render and Lint the Chart:**

   ```bash
   helm template creating-charts/nginx
   helm lint creating-charts/nginx
   ```

   The rendered manifests match exercise 01's, except for the 3 replicas and the quotes around the image value.
   The Service renders `type: ClusterIP`, `port: 80`, and `targetPort: 80`, and the Deployment renders `image: "nginx:1.27.0"` and `containerPort: 80`.
   `helm lint` reports only `[INFO] Chart.yaml: icon is recommended`.

## Conclusion

In this exercise, we defined the chart's first values in `values.yaml`, documented them, and referenced them in the Deployment and Service templates through the `.Values` object.
