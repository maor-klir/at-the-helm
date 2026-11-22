# Bootstrapping the config-store chart

## Overview

In this exercise, we'll create a chart for config-store with `helm create`, configure its image, resources, and security contexts, and install it to see why it needs a database.
Here's a quick summary of the main steps:

1. Create the chart in a `subcharts` directory.
2. Set the resources, the security contexts, the Service type, and the image.
3. Lint and render the chart.
4. Install it, and see the application fail without a database.

## Step-by-step guide

Run the commands from this folder. The chart in `subcharts/config-store/` is the end state of this exercise.
To build the chart yourself, run the steps in an empty directory, then compare your files with the ones here.

1. **Create the chart:**

   ```bash
   mkdir subcharts
   cd subcharts
   helm create config-store
   ```

   The chart in this folder comes from the Helm 3 scaffold the course used. Helm 4's scaffold differs in three places:

   | Helm 4 scaffold | Effect |
   |---|---|
   | `templates/httproute.yaml` and an `httpRoute` block in `values.yaml` | a Gateway API route, off by default like the Ingress |
   | `with` blocks around the security contexts, probes, and resources in `deployment.yaml` | an empty value renders nothing instead of `{}` |
   | `image.tag: ""` | the tag falls back to `appVersion` |

   The Ingress and the HTTPRoute stay off: `ingress.enabled` and `httpRoute.enabled` are `false`.

2. **Set the resources:**

   Replace `resources: {}` and the commented example below it in `values.yaml`. The blocks in this exercise leave out the scaffold's comments:

   ```yaml
   resources:
     limits:
       cpu: 200m
       memory: 256Mi
     requests:
       cpu: 100m
       memory: 128Mi
   ```

   An empty map and keys can't share one entry, so the `{}` has to go. The application uses about 38 MiB, well within these limits (see **41 - The config-store application**).

3. **Set the security contexts:**

   Uncomment the examples, and remove each `{}`:

   ```yaml
   podSecurityContext:
     fsGroup: 2000

   securityContext:
     capabilities:
       drop:
         - ALL
     readOnlyRootFilesystem: true
     runAsNonRoot: true
     runAsUser: 1000
   ```

   The image was built to run as root, and works as UID 1000 with a read-only root filesystem and no capabilities (see **41 - The config-store application**).

4. **Set the Service type and the image:**

   ```yaml
   image:
     repository: ghcr.io/maor-klir/config-store
     pullPolicy: IfNotPresent
     tag: '1.0.0'
   ```

   ```yaml
   service:
     type: NodePort
     port: 80
   ```

   The course uses its own image, `lmacademy/config-store:1.0.0`; this chart uses ours, built and pushed in the config-store section.
   With `IfNotPresent`, a node keeps the image it already has, so a rebuilt image needs a new tag; reusing a tag needs `pullPolicy: Always` instead (see **43 - The application image**).

   The course uses `NodePort` to reach the Service from minikube. Node ports on k3d-argocd aren't reachable from the laptop, so `kubectl port-forward` reaches the Service either way.

5. **Set the chart's application version:**

   In `Chart.yaml`, set `appVersion: '1.0.0'`. The Deployment's image line falls back to it when `image.tag` is empty:

   ```yaml
   image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
   ```

   `autoscaling.enabled` stays `false`. k3d-argocd already runs metrics-server, which a HorizontalPodAutoscaler needs: `kubectl -n kube-system get deployment metrics-server` shows it `1/1` ready.

6. **Lint and render the chart:**

   From the `subcharts` directory:

   ```bash
   helm lint config-store
   helm template config-store ./config-store | grep '^kind'
   ```

   The lint ends with `1 chart(s) linted, 0 chart(s) failed`. The chart renders a ServiceAccount, a Service, a Deployment, and a Pod; the Pod is a test from `templates/tests/`, which the advanced topics section covers.

7. **Install the chart:**

   ```bash
   helm -n config-store install config-store ./config-store --create-namespace
   kubectl -n config-store get pods -w
   ```

   Helm reports `STATUS: deployed` right away: without `--wait`, it waits only for hooks, not for the Pod.
   The node pulls the image from GHCR without a pull Secret, since the package is public. The Pod then alternates between `Error` and `CrashLoopBackOff`, its restart count grows, and the probes fail with `connection refused` on port 80.

   The container's logs show why:

   ```bash
   kubectl -n config-store logs deployment/config-store
   ```

   ```text
   TypeError [ERR_INVALID_ARG_TYPE]: The "url" argument must be of type string. Received undefined
       at Url.parse (node:url:177:3)
       at Object.urlParse [as parse] (node:url:148:13)
       at new Sequelize (/app/node_modules/sequelize/lib/sequelize.js:57:28)
   ```

   The chart sets no `DB_URL`, so Sequelize receives `undefined` and the process exits with code 1 before it listens.
   It also sets no `PORT`, so the application would listen on 3000 while the container port and the probes use 80. Exercise 07 sets both.

8. **Clean up:**

   ```bash
   helm -n config-store uninstall config-store
   kubectl delete namespace config-store
   ```

   `helm uninstall` removes the Deployment, the Service, and the ServiceAccount; the namespace isn't part of the release.

## Conclusion

In this exercise, we created the config-store chart with `helm create`, configured its image, resources, and security contexts, and saw the application crash without a database.
Exercise 02 adds PostgreSQL as a chart dependency.
