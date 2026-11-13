# Conditionally Deploying the Service

## Overview

In this exercise, we're going to give users the option to turn off the Service in our Nginx chart.
Currently, the Service is always deployed; a new `service.enabled` value will decide whether it's rendered at all.

Here’s a quick summary of the main steps you should aim to complete:

1. Add a documented `enabled` parameter to the `service` section of `values.yaml`, with a default of `true`.
2. Wrap the whole Service template in an `if` condition on `.Values.service.enabled`.
3. Render the chart with the Service enabled and disabled.
4. Install the chart with the Service disabled, then turn it on and off again with upgrades.

## Step-by-Step Guide

Run the commands from this folder. The chart in `creating-charts/nginx/` is the end state of this exercise.
It continues from exercise 06's chart, so to follow the steps, copy `../06-use-release-chart-information/creating-charts` into an empty directory and edit that copy.

1. **Add the `enabled` Parameter:**

   Add `enabled` to the service settings in `values.yaml`, with its own `@param` line:

   ```yaml
   ## Settings for NGINX service
   ##
   ## @param service.enabled Whether to deploy the service altogether or not
   ## @param service.type The type of service in front of the Nginx pods
   ## @param service.port The port where the service is receiving requests
   service:
     enabled: true
     type: ClusterIP
     port: 80
   ```

2. **Wrap the Service Template:**

   Wrap all of `templates/service.yaml` in an `if` and close it with an `end`.
   This is the file in `creating-charts/nginx/templates/service.yaml`:

   ```yaml
   {{- if .Values.service.enabled }}
   apiVersion: v1
   kind: Service
   metadata:
     name: {{ .Release.Name }}-{{ .Chart.Name }}-svc
     labels:
       app: {{ .Chart.Name }}
       release: {{ .Release.Name }}
   spec:
     type: {{ .Values.service.type }}
     selector:
       app: {{ .Chart.Name }}
       release: {{ .Release.Name }}
     ports:
       - protocol: TCP
         port: {{ .Values.service.port }}
         targetPort: {{ .Values.containerPorts.http }}
   {{ end }}
   ```

   Everything between `if` and `end` renders only when the condition is true.
   Helm's control structures guide lists what counts as false: "a boolean false", "a numeric zero", "an empty string", "a `nil` (empty or null)", and "an empty collection"; "Under all other conditions, the condition is true."

   The dash in `{{- if` trims whitespace before the action. At the top of the file there's none, so here it changes nothing.

3. **Render with the Service Enabled and Disabled:**

   ```bash
   helm template creating-charts/nginx
   helm template creating-charts/nginx --set service.enabled=false
   ```

   The first command renders the Service and the Deployment.
   The second renders only the Deployment: the Service document disappears completely, and `helm template creating-charts/nginx --set service.enabled=false -s templates/service.yaml` reports `could not find template templates/service.yaml in chart`.

   The value has to be a boolean.
   `--set-string service.enabled=false`, or `enabled: "false"` in a values file, passes the string `"false"`, which isn't empty and so counts as true: the Service is still rendered.
   Helm's best practices warn about exactly this: "`foo: false` is not the same as `foo: "false"`."

   A missing value counts as false: with `--set service.enabled=null`, which removes the key, no Service is rendered. That's why the default of `true` belongs in `values.yaml`.

4. **Install with the Service Disabled:**

   ```bash
   helm -n nginx install local-nginx creating-charts/nginx --create-namespace --set service.enabled=false
   kubectl -n nginx get deploy,svc
   ```

   Only the Deployment is created; there's no Service:

   ```text
   NAME                                READY   UP-TO-DATE   AVAILABLE   AGE
   deployment.apps/local-nginx-nginx   3/3     3            3           3s
   ```

   Turning the Service on later is an upgrade, and turning it off again removes it:

   ```bash
   helm -n nginx upgrade local-nginx creating-charts/nginx --set service.enabled=true
   kubectl -n nginx get svc
   helm -n nginx upgrade local-nginx creating-charts/nginx --set service.enabled=false
   kubectl -n nginx get svc
   ```

   The first upgrade, revision 2, creates `local-nginx-nginx-svc`, a `ClusterIP` Service on port 80.
   The second, revision 3, deletes it, and `kubectl -n nginx get svc` finds no resources again: Helm removes the objects a new revision no longer renders.

5. **Clean Up:**

   ```bash
   helm -n nginx uninstall local-nginx
   kubectl delete namespace nginx
   ```

## Conclusion

In this exercise, we made the Service optional by wrapping its template in an `if` on `.Values.service.enabled`.
The same pattern works inside a template too, to include or leave out individual fields or blocks depending on the values.
