# Creating an Nginx Helm Chart

## Overview

In this exercise, we'll be diving into the process of creating our very first Helm chart for deploying Nginx to Kubernetes.

Here’s a quick overview of what we’ll be doing:

1. Create a new directory to hold your Helm chart.
2. Create the `Chart.yaml` file containing metadata about your chart.
3. Generate an empty `values.yaml` file to hold configuration values later on.
4. Establish a `templates` directory that will contain the Helm templates for the Kubernetes manifests.
5. Develop `deployment.yaml` and `service.yaml` files for your Nginx deployment.
6. Add a `.helmignore` file.
7. Utilize the Helm template command to generate Kubernetes manifests from your chart.
8. Validate your chart using the `helm lint` command.
9. Install the chart, check its Pod and Service, and uninstall it.

## Step-by-Step Guide

Run the commands from this folder. The finished chart is already in `creating-charts/nginx/`, so steps 1 to 8 describe its files.

To build the chart yourself, run those steps in an empty directory instead, then compare your files with the ones here.

1. **Create a New Directory:**

   ```bash
   mkdir creating-charts
   ```

2. **Create the Nginx Chart Directory:**

   Inside it, create the chart's directory, `nginx`:

   ```bash
   mkdir creating-charts/nginx
   ```

   Helm takes the chart's name from `Chart.yaml`, not from the directory, so a name such as `nginx-chart` works as well.

3. **Create `Chart.yaml`:**

   Inside `creating-charts/nginx`, create a file called `Chart.yaml` with the following content:

   ```yaml
   apiVersion: v2
   name: nginx
   description: A Helm chart for deploying Nginx to Kubernetes
   type: application
   version: 0.1.0
   appVersion: 1.27.0
   ```

   The file name is case-sensitive: with `chart.yaml`, Helm stops with `unable to detect chart`.
   `apiVersion: v2` is the chart format for Helm 3 and Helm 4. `version` is the chart's own version, and `appVersion` is the version of Nginx it deploys.

4. **Generate `values.yaml`:**

   Create an empty `values.yaml`. It stays empty until the templates read values from it:

   ```bash
   touch creating-charts/nginx/values.yaml
   ```

5. **Create the `templates` Directory:**

   Helm renders every file in this directory into the Kubernetes manifests it installs:

   ```bash
   mkdir creating-charts/nginx/templates
   ```

6. **Write `deployment.yaml`:**

   Inside `templates`, create a `deployment.yaml` file and populate it as follows:

   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: nginx
     labels:
       app: nginx
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: nginx
     template:
       metadata:
         labels:
           app: nginx
       spec:
         containers:
           - name: nginx
             image: nginx:1.27.0
             ports:
               - containerPort: 80
   ```

   The Pod template's labels must match `spec.selector.matchLabels`. The API server rejects a Deployment whose selector doesn't match them: `` `selector` does not match template `labels` ``.

7. **Create `service.yaml`:**

   Next to it, create a `service.yaml` file with this content:

   ```yaml
   apiVersion: v1
   kind: Service
   metadata:
     name: nginx-svc
     labels:
       app: nginx
   spec:
     type: ClusterIP
     selector:
       app: nginx
     ports:
       - protocol: TCP
         port: 80
         targetPort: 80
   ```

   The Service selects the Pods by the same `app: nginx` label.

8. **Create `.helmignore`:**

   This file is optional. Create `creating-charts/nginx/.helmignore` with these patterns:

   ```text
   .env*
   .DS_Store*
   .git/
   ```

   `.env*` keeps local environment files, which can hold secrets, out of the chart.
   `.DS_Store*` matches the metadata files macOS Finder creates, and `.git/` a Git directory, in case the chart has its own repository.
   Helm applies these patterns whenever it loads the chart from a directory: in `helm package`, and also in `helm template`, `helm install`, and `helm upgrade`.

9. **Render the Templates:**

   ```bash
   helm template creating-charts/nginx
   ```

   The output holds two manifests, each under a `# Source:` comment that names its template. Helm sorts them by kind, so the Service comes before the Deployment. From inside `creating-charts/nginx`, the chart path is `.`.

10. **Lint the Chart:**

    ```bash
    helm lint creating-charts/nginx
    ```

    ```text
    ==> Linting creating-charts/nginx
    [INFO] Chart.yaml: icon is recommended

    1 chart(s) linted, 0 chart(s) failed
    ```

    `[INFO]` is a suggestion, not an error.

    `helm lint` checks `Chart.yaml` and renders the templates, but it doesn't send the objects to the API server.
    A misspelled field such as `replica: 1`, or Pod labels that don't match the selector, pass `helm lint`, and in Helm 4.3.2 they also pass `helm install --dry-run=server`.

    To have the API server validate every object without creating anything, pipe the rendered manifests to `kubectl apply --dry-run=server`. The `nginx` namespace doesn't exist yet, so the check runs in `default`:

    ```bash
    helm template creating-charts/nginx | kubectl -n default apply --dry-run=server -f -
    ```

    Both objects come back as `created (server dry run)`. With the misspelled field, the API server rejects the Deployment: `strict decoding error: unknown field "spec.replica"`.

11. **Install the Chart:**

    Install the chart as release `local-nginx`, in its own namespace:

    ```bash
    helm -n nginx install local-nginx creating-charts/nginx --create-namespace
    ```

    Helm 4 applies the objects with server-side apply and, without `--wait`, returns without waiting for the Pod. Add `--wait` to make it wait until the Deployment is ready.

12. **Check the Pod and Service:**

    ```bash
    kubectl -n nginx get pods,svc
    ```

    The `nginx-…` Pod is `Running`, and `nginx-svc` is a `ClusterIP` Service. To check that the Service reaches the Pod, forward a local port to it and request the Nginx welcome page:

    ```bash
    kubectl -n nginx port-forward svc/nginx-svc 9090:80 > /dev/null 2>&1 &
    sleep 2; curl -s http://localhost:9090 | grep '<title>'
    kill %1
    ```

    The page title is `<title>Welcome to nginx!</title>`.

13. **Clean Up:**

    Once you've validated your Helm chart, uninstall it and delete the namespace:

    ```bash
    helm -n nginx uninstall local-nginx
    kubectl -n nginx get pods,svc
    kubectl delete namespace nginx
    ```

    Once the Pod has terminated, the second command finds no resources.
    The chart has no PersistentVolumeClaims, so nothing else is left behind.
    Helm doesn't delete the namespace that `--create-namespace` created, because the namespace isn't part of the release.

## Conclusion

In this exercise, we started with some essential Kubernetes manifests and set the stage for future enhancements using Go templating.
