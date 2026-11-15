# Installing NGINX from Our Helm Repository

## Overview

In this guide, we'll install our Nginx chart from the chart repository published in exercise 09, the same way we installed charts from the Bitnami and Prometheus community repositories.

Here's a high-level overview of what you will be doing:

1. Add your chart repository to Helm, using its GitHub Pages URL.
2. List your repositories to confirm the addition.
3. Search for the Nginx chart.
4. Install the chart from the repository.
5. Verify the installation, then uninstall it.

## Step-by-Step Guide

The chart repository is `https://maor-klir.github.io/helm-charts`, from exercise 09.

1. **Add the Repository:**

   Add the repository under a name of your choice; your GitHub username works well:

   ```bash
   helm repo add maor-klir https://maor-klir.github.io/helm-charts
   ```

   Use the repository's base URL, without `index.yaml`: Helm appends `/index.yaml` itself.
   With the file name included, the request goes to `…/helm-charts/index.yaml/index.yaml`, and `helm repo add` fails with `404 Not Found`.

2. **Confirm the Repository Addition:**

   ```bash
   helm repo list
   ```

   `maor-klir` is listed next to the repositories added earlier, such as `bitnami` and `prometheus-community`:

   ```text
   NAME                	URL
   argo                	https://argoproj.github.io/argo-helm
   kyverno             	https://kyverno.github.io/kyverno/
   prometheus-community	https://prometheus-community.github.io/helm-charts
   bitnami             	https://charts.bitnami.com/bitnami
   maor-klir           	https://maor-klir.github.io/helm-charts
   ```

3. **Search for the Nginx Chart:**

   ```bash
   helm search repo nginx
   ```

   The search covers every added repository, so Bitnami's charts that match "nginx" are listed together with ours:

   ```text
   NAME                            	CHART VERSION	APP VERSION	DESCRIPTION
   bitnami/nginx                   	25.2.14      	1.31.8     	NGINX Open Source is a web server that can be a...
   bitnami/nginx-ingress-controller	12.0.7       	1.13.1     	NGINX Ingress Controller is an Ingress controll...
   bitnami/nginx-intel             	2.1.15       	0.4.9      	DEPRECATED NGINX Open Source for Intel is a lig...
   maor-klir/nginx                 	0.1.0        	1.27.0     	A Helm chart for deploying Nginx to Kubernetes
   ```

   `helm search repo maor-klir/` lists only our repository's charts, and `helm show chart maor-klir/nginx` prints the chart's metadata.

   The search reads the local copy of each repository's index. After you publish a new chart version, run `helm repo update maor-klir` before searching for or installing it.

4. **Install the Chart:**

   Install the chart as release `super-nginx`, using the `<repository>/<chart>` reference from the search:

   ```bash
   helm -n nginx install super-nginx maor-klir/nginx --create-namespace
   ```

5. **Verify the Installation:**

   ```bash
   kubectl -n nginx get deploy,svc,pods
   ```

   The Deployment and Service are named after the release and the chart, and the three Pods' names start with the Deployment's name:

   ```text
   NAME                                READY   UP-TO-DATE   AVAILABLE   AGE
   deployment.apps/super-nginx-nginx   3/3     3            3           2s

   NAME                            TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)   AGE
   service/super-nginx-nginx-svc   ClusterIP   10.43.45.93   <none>        80/TCP    2s

   NAME                                     READY   STATUS    RESTARTS   AGE
   pod/super-nginx-nginx-6c5b979b9f-jqhq9   1/1     Running   0          2s
   pod/super-nginx-nginx-6c5b979b9f-rnwb5   1/1     Running   0          2s
   pod/super-nginx-nginx-6c5b979b9f-xd88n   1/1     Running   0          2s
   ```

   `helm -n nginx list` shows the release's chart as `nginx-0.1.0`, the version published in the repository.

6. **Clean Up:**

   ```bash
   helm -n nginx uninstall super-nginx
   kubectl delete namespace nginx
   ```

   The repository can stay added; exercise 11 doesn't need it, and `helm repo remove maor-klir` removes it.

## Conclusion

In this exercise, we closed the cycle of creating our own chart: we wrote it, rendered and linted it, packaged it, published it in a chart repository, and installed a release from that repository.
