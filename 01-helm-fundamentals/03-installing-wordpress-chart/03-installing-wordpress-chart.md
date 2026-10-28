# Installing Your First Helm Chart

## Overview

Welcome to our practical guide on installing your first Helm chart! This exercise is a great opportunity to dive into the Helm ecosystem and learn how to deploy applications in a Kubernetes cluster seamlessly.

In this exercise, we'll be installing a WordPress application using a Helm chart from the Bitnami repository. To give you a head start before we jump into the step-by-step guide, here’s an outline of what you'll be doing:

1. Ensure your Kubernetes cluster is running. Check the status using `kubectl version`.
2. Add the Bitnami repository to your Helm repositories (if not yet done so).
3. Search for the WordPress chart within this repository.
4. Install a specific version of the WordPress chart using the `helm install` command.
5. Verify the installation by checking the pods and services created.
6. Expose the application to access it from your browser.

## Step-by-Step Guide

1. Ensure your Kubernetes cluster is up and running. You can do this by running:
   ```bash
   kubectl version
   ```
2. If your cluster is running fine, add the Bitnami Helm repository:
   ```bash
   helm repo add bitnami https://charts.bitnami.com/bitnami
   helm repo update
   ```
3. Search for the WordPress chart to find its exact name:

   ```bash
   helm search repo wordpress
   ```

4. Choose the version you want to install (e.g., 23.1.20) and use the `helm install` command:

   ```bash
   helm -n wordpress install local-wp bitnami/wordpress --version 23.1.20 --create-namespace --values ./wp-repo-overrides.yaml
   ```

   > **Bitnami images moved:** the versioned image tags this chart uses are gone from `docker.io/bitnami` and now live in `docker.io/bitnamilegacy`. `./wp-repo-overrides.yaml` sets `image.repository` and `mariadb.image.repository` to the `bitnamilegacy` images. Pass it on every `helm template`, `install`, and `upgrade` of WordPress 23.1.x, running the commands from this folder. Without it, the pods fail with `ErrImagePull`.

5. Check the status of the pods to ensure they are running:

   ```bash
   kubectl -n wordpress get pods
   ```

6. The chart already exposes WordPress with a `LoadBalancer` Service, `local-wp-wordpress`:

   ```bash
   kubectl -n wordpress get svc
   ```

   > **k3d-argocd cluster:** k3s's built-in ServiceLB gives the Service the node IPs as external IPs (`172.18.0.2`, `172.18.0.3`, `172.18.0.5`). Those addresses are on the k3d Docker network on the home server, so the laptop can't reach them. A `NodePort` Service has the same problem, so `kubectl expose` isn't needed.

7. Forward a local port to the Service, silently in the background:

   ```bash
   kubectl -n wordpress port-forward svc/local-wp-wordpress 9090:80 > /dev/null 2>&1 &
   ```

   Open `http://localhost:9090` in your browser, and you should see your WordPress site up and running. If the page doesn't load, check with `jobs` that the forward is still running. Stop it with `kill %1`.

   > **Through the LoadBalancer IPs:** the home server can reach the Docker network, so an SSH tunnel through it works too: `ssh -N -L 8080:172.18.0.5:80 pi-hole`, then open `http://localhost:8080`.

## Conclusion

Congratulations on successfully deploying your first application using Helm! This exercise has hopefully shown you how straightforward it is to manage applications with Helm charts. Keep exploring the various options Helm provides, and you'll find that your skills will increase significantly.