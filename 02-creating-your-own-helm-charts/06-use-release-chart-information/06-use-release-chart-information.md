# Using Release and Chart Information in Templates

## Overview

In this exercise, we'll replace the hardcoded `nginx` names and labels in our templates with values from the `.Release` and `.Chart` objects.
Our goal is to let the same chart be installed more than once in a namespace, with each release managing only its own objects.

Here's what you should aim to implement:

1. Name the Deployment and Service after the release and the chart, using `.Release.Name` and `.Chart.Name`.
2. Add a `release` label to the labels and selectors, so each release selects only its own Pods.
3. Install the chart twice and check that both releases run side by side.
4. Inspect the labels and annotations on the Deployment and its Pods.

## Step-by-Step Guide

Run the commands from this folder. The chart in `creating-charts/nginx/` is the end state of this exercise.
It continues from exercise 05's chart, so to follow the steps, copy `../05-add-first-values-template/creating-charts` into an empty directory and edit that copy.

1. **See Why Fixed Names Conflict:**

   Kubernetes requires each object's name to be unique within its kind and namespace: "Each object in your cluster has a Name that is unique for that type of resource."
   With exercise 05's chart, every release creates a Deployment named `nginx` and a Service named `nginx-svc`, so a second release of the same chart can't be installed next to the first.

   ```bash
   helm -n nginx install local-nginx ../05-add-first-values-template/creating-charts/nginx --create-namespace
   helm -n nginx install local-nginx-2 ../05-add-first-values-template/creating-charts/nginx
   ```

   The second install fails, because `nginx-svc` already exists and belongs to `local-nginx`:

   ```text
   Error: INSTALLATION FAILED: unable to continue with install: Service "nginx-svc" in namespace "nginx" exists and cannot be imported into the current release: invalid ownership metadata; annotation validation error: key "meta.helm.sh/release-name" must equal "local-nginx-2": current value is "local-nginx"
   ```

   Helm checks this before it creates anything, so the failed install leaves no release behind: `helm -n nginx list` shows only `local-nginx`.
   Helm's chart template guide calls this out: "Hard-coding the `name:` into a resource is usually considered to be bad practice. Names should be unique to a release."

   Uninstall the first release before continuing:

   ```bash
   helm -n nginx uninstall local-nginx
   ```

2. **Name Objects After the Release and Chart:**

   In `templates/deployment.yaml`, build the name from both objects:

   ```yaml
   name: {{ .Release.Name }}-{{ .Chart.Name }}
   ```

   In `templates/service.yaml`, do the same with a `-svc` suffix:

   ```yaml
   name: {{ .Release.Name }}-{{ .Chart.Name }}-svc
   ```

   `.Release.Name` is the name passed to `helm install`, and `.Chart.Name` is the `name` field of `Chart.yaml`.
   `helm template local-nginx creating-charts/nginx` renders `local-nginx-nginx` and `local-nginx-nginx-svc`.

   Release names are unique within a namespace, so names that start with the release name are unique too.
   They also have a length limit: "The `name:` field is limited to 63 characters because of limitations to the DNS system. For that reason, release names are limited to 53 characters."

   > **The repeated `nginx`:** `helm create` avoids names like `local-nginx-nginx`.
   > Its `fullname` helper uses the release name alone when it already contains the chart name, and truncates the result to 63 characters.
   > Exercise 11 covers `helm create`.

3. **Make the Labels Unique per Release:**

   Names aren't the only thing two releases share. With only `app: nginx`, each release's Deployment selector and Service selector would also match the other release's Pods.
   The Kubernetes Deployment documentation warns against this: "Do not overlap labels or selectors with other controllers (including other Deployments and StatefulSets). Kubernetes doesn't stop you from overlapping, and if multiple controllers have overlapping selectors those controllers might conflict and behave unexpectedly."

   Add a `release` label next to `app` in the Deployment's labels, its `spec.selector.matchLabels`, and its Pod template's labels:

   ```yaml
   app: {{ .Chart.Name }}
   release: {{ .Release.Name }}
   ```

   Use the same two labels for the Service's labels and its `selector`.

   Choose selector labels before the first install: a Deployment's `spec.selector` is immutable, so changing the selector labels later makes `helm upgrade` fail for existing releases.

   Helm's best practices recommend standard names for these two labels: `app.kubernetes.io/name` for the application, and `app.kubernetes.io/instance` for the release, described as "This should be the `{{ .Release.Name }}`. It aids in differentiating between different instances of the same application."
   The `helm create` scaffold uses both as its selector labels; this chart keeps the shorter `app` and `release`.

4. **Install Two Releases:**

   ```bash
   helm -n nginx install local-nginx creating-charts/nginx
   helm -n nginx install local-nginx-2 creating-charts/nginx
   kubectl -n nginx get deploy,rs,pods
   ```

   Both installs succeed.
   With `replicaCount: 3`, each release runs three Pods, so the namespace holds two Deployments, `local-nginx-nginx` and `local-nginx-2-nginx`, two ReplicaSets, and six Pods.

   Installing a release under a name that's already in use fails instead, because release names can't repeat within a namespace:

   ```text
   Error: INSTALLATION FAILED: release name check failed: cannot reuse a name that is still in use
   ```

5. **Inspect Labels and Annotations:**

   ```bash
   kubectl -n nginx get pods --show-labels
   kubectl -n nginx describe deployment local-nginx-nginx
   ```

   Each Pod carries `app=nginx` and the `release` label of its own release, plus the `pod-template-hash` label the Deployment adds.
   The Service selects only its own release's Pods: its EndpointSlice lists the three `local-nginx-nginx-…` Pods and none of `local-nginx-2`'s.

   ```bash
   kubectl -n nginx get endpointslices -l kubernetes.io/service-name=local-nginx-nginx-svc -o jsonpath='{range .items[*].endpoints[*]}{.targetRef.name}{"\n"}{end}'
   ```

   The Deployment also carries metadata the chart doesn't define. Helm adds a label and two annotations to every object it creates, here the Deployment and the Service:

   ```text
   Labels:                 app=nginx
                           app.kubernetes.io/managed-by=Helm
                           release=local-nginx
   Annotations:            deployment.kubernetes.io/revision: 1
                           meta.helm.sh/release-name: local-nginx
                           meta.helm.sh/release-namespace: nginx
   Selector:               app=nginx,release=local-nginx
   ```

   These are what Helm checked in step 1.
   The ReplicaSet gets the two annotations as well, because the Deployment controller copies the Deployment's annotations to it, but not the `managed-by` label: its labels come from the Pod template.
   The Pods have neither: their labels come only from the Pod template, and they have no annotations.

6. **Clean Up:**

   ```bash
   helm -n nginx uninstall local-nginx local-nginx-2
   kubectl delete namespace nginx
   ```

## Conclusion

In this exercise, we removed the hardcoded `nginx` names and labels from our templates and built them from `.Release.Name` and `.Chart.Name`.
Each release now has its own Deployment, Service, and selector labels, so the same chart can be installed several times in one namespace.
