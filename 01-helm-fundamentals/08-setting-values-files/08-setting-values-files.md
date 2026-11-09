# Setting Custom Values with YAML Files in Helm

## Overview

In this lecture, we’ll learn how to manage our WordPress release better by leveraging YAML file configurations, providing a cleaner and more maintainable solution.

In this exercise, you will implement a system that allows you to set custom values for your WordPress release using a YAML file. Before diving into the step-by-step guide, I encourage you to try and accomplish the following on your own:

1. Check that no WordPress release is installed.
2. Create a YAML file to define custom values for WordPress.
3. Securely manage WordPress credentials by using a Kubernetes Secret.
4. Increase the replica count for your WordPress deployment.

## Step-by-Step Guide

Here’s how to set custom values for your WordPress release using a YAML file. Run the commands from this folder:

1. **Check for Installed Releases:**

   ```bash
   helm -n wordpress list
   ```

   No release should be listed. The install in step 4 creates `local-wp` from scratch.

2. **Create a YAML File:**

   `custom-values.yaml` in this folder sets the image repositories, the WordPress admin username, an existing Secret for the password, and the replica count:

   ```yaml
   image:
     repository: bitnamilegacy/wordpress
   mariadb:
     image:
       repository: bitnamilegacy/mariadb

   wordpressUsername: maor
   existingSecret: custom-wp-credentials
   replicaCount: 3
   ```

   These are the WordPress admin credentials, not the MariaDB ones from exercise 07.
   The password stays out of the file. The chart's `values.yaml` says about `existingSecret`: "NOTE: Must contain key `wordpress-password`" and "NOTE: When it's set, the `wordpressPassword` parameter is ignored".

   > **Bitnami images moved:** the first block is the `bitnamilegacy` override from exercise 03, so this one file is all the install needs.

3. **Manage Sensitive Values:**

   The Secret has to exist before the install, and the namespace before the Secret:

   ```bash
   kubectl create namespace wordpress
   read -rs WP_PW
   kubectl -n wordpress create secret generic custom-wp-credentials --from-literal=wordpress-password="$WP_PW"
   unset WP_PW
   ```

   `read -rs` reads the password without echoing it, so it doesn't end up in the shell history the way a literal `--from-literal=wordpress-password=…` would.
   The Secret's name has no `local-wp-` prefix, so it isn't mistaken for an object the release created.

4. **Install with the YAML File:**

   ```bash
   helm -n wordpress install local-wp bitnami/wordpress --version 23.1.20 --values custom-values.yaml
   helm -n wordpress get values local-wp
   ```

   `helm get values` lists the image repositories, `wordpressUsername`, `existingSecret`, and `replicaCount` under `USER-SUPPLIED VALUES:`.

5. **Verify the Installation:**

   ```bash
   kubectl -n wordpress get pods --watch
   ```

   Three WordPress Pods start next to the MariaDB Pod.

   > **k3d-argocd cluster:** the chart README lists "ReadWriteMany volumes for deployment scaling" as a prerequisite, while k3s's `local-path` volumes are `ReadWriteOnce`.
   > The volume is bound to one node, so the scheduler runs all three WordPress Pods on that node: `kubectl -n wordpress get pods -o wide` shows them on the same node as the volume.

6. **Log In with the Custom Credentials:**

   ```bash
   kubectl -n wordpress port-forward svc/local-wp-wordpress 9090:80 > /dev/null 2>&1 &
   ```

   Open `http://localhost:9090/wp-admin` and log in as `maor` with the password stored in the Secret:

   ```bash
   kubectl -n wordpress get secret custom-wp-credentials -o jsonpath='{.data.wordpress-password}' | base64 -d; echo
   ```

   Keep the release installed: exercises 09 to 12 upgrade it. Stop the port-forward with `kill %1` when you're done.

## Conclusion

In this lecture, we learned how to set custom values for a WordPress release with a YAML file, emphasizing the importance of managing sensitive information securely.
By implementing these practices, you enhance the maintainability and security of your Helm charts.
