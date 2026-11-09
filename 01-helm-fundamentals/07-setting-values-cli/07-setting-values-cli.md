# Setting Values via CLI in Helm

## Overview

In this exercise, we're going to dive into how to override the default values provided in the WordPress Helm chart by providing our own values through the CLI.

In this exercise, we'll be focusing on the following main steps to implement custom configuration values for your WordPress deployment using Helm:

1. **Explore the Default Values:** Review the default configuration values of the WordPress chart.
2. **Identify Key Parameters:** Identify the specific parameters you want to set (like root and user passwords for MariaDB).
3. **Use CLI to Set Values:** Execute the Helm install command using the `--set` flag to specify your own values for the identified parameters.
4. **Verify Deployment:** Check the deployment status and logs to ensure everything is running correctly.
5. **Inspect Secrets:** Verify that the passwords set in your command are correctly reflected in the Kubernetes Secrets.
6. **Reinstall with the Same Values:** Uninstall, keep the MariaDB volume, and confirm that a reinstall with the same passwords starts.

## Step-by-Step Guide

Run the commands from this folder.

1. **Find the Values to Override:**

   On Artifact Hub, select chart version 23.1.20 (the page opens on the latest version, 34.x) and look for the MariaDB authentication parameters. Or print them from the CLI:

   ```bash
   helm show values bitnami/wordpress --version 23.1.20 --jsonpath '{.mariadb.auth}'
   ```

   The keys are nested under `mariadb.auth`: `rootPassword` is the MariaDB root password, and `password` is the password of the `bn_wordpress` user that WordPress connects with. `username` and `database` can be overridden the same way.

   > **Corrected keys:** the original exercise text used `mariadb.rootPassword` and `mariadb.userPassword`, which don't exist in chart 23.1.20. Helm accepts them without an error, and the passwords stay random.

2. **Install with `--set`:**

   Each `--set` takes the full dotted path of a value:

   ```bash
   helm -n wordpress install local-wp bitnami/wordpress --version 23.1.20 --create-namespace \
     --values ../03-installing-wordpress-chart/wp-repo-overrides.yaml \
     --set mariadb.auth.rootPassword=myAwesomePassword \
     --set mariadb.auth.password=myUserPassword
   ```

   > **Bitnami images moved:** pin `--version 23.1.20` and pass the `bitnamilegacy` overrides file (see exercise 03).

   > **Sensitive values:** a password typed after `--set` ends up in the shell history, and Helm stores user-supplied values in the release record, where `helm get values` prints them in plain text.
   > For real passwords, pass them through variables, e.g. `--set mariadb.auth.rootPassword="$MARIADB_ROOT_PASSWORD"`, and never commit them to this repository.
   > Exercise 08 takes the WordPress password from an existing Secret instead.

3. **Monitor the Deployment:**

   ```bash
   kubectl -n wordpress get pods --watch
   kubectl -n wordpress logs deploy/local-wp-wordpress
   ```

   After about a minute, both Pods are ready, and the WordPress log gets past `Trying to connect to the database server`.

4. **Verify Secrets:**

   ```bash
   kubectl -n wordpress get secret local-wp-mariadb -o jsonpath='{.data.mariadb-password}' | base64 -d; echo
   kubectl -n wordpress get secret local-wp-mariadb -o jsonpath='{.data.mariadb-root-password}' | base64 -d; echo
   helm -n wordpress get values local-wp
   ```

   The Secret holds `myUserPassword` and `myAwesomePassword` instead of random strings. `helm get values` lists both under `USER-SUPPLIED VALUES:`, next to the image repositories from the overrides file.

5. **Uninstall and Reinstall with the Same Values:**

   ```bash
   helm -n wordpress uninstall local-wp
   kubectl -n wordpress get pvc
   ```

   `data-local-wp-mariadb-0` is still there, as in exercise 06. Run the install command from step 2 again, with the same `--set` flags. This time the passwords match the data on the retained volume, so both Pods become ready.

6. **Clean Up:**

   ```bash
   helm -n wordpress uninstall local-wp
   kubectl -n wordpress delete pvc data-local-wp-mariadb-0
   kubectl delete namespace wordpress
   ```

## Conclusion

In this lecture, we learned how to override default configuration values in the WordPress Helm chart using the CLI.
By setting specific parameters like the root and user passwords for MariaDB, we can maintain consistency and ensure smoother deployments.
