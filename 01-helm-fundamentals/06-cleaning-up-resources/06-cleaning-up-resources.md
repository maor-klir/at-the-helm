# Exploring Generated Values and Persistent Data in Helm

## Overview

In this guide, we'll explore how Helm interacts with persistent data through the installation and uninstallation of WordPress. You'll learn what can happen if PersistentVolumeClaims aren't properly managed. Before diving into the step-by-step guide, I encourage you to challenge yourself and try implementing the solution based on the overview provided.

In this exercise, you'll focus on understanding the implications of not deleting PersistentVolumeClaims when uninstalling a Helm release. The main steps you should try to implement are:

1. Install the Bitnami WordPress chart.
2. Retrieve the generated passwords from the MariaDB and WordPress Secrets.
3. Uninstall the WordPress release using `helm uninstall`.
4. Verify that the Secrets have been removed while the PersistentVolumeClaims remain.
5. Attempt to install WordPress again and observe any issues that arise due to configuration mismatches.
6. Manually delete the PersistentVolumeClaim for the MariaDB data.

## Step-by-Step Guide

Run the commands from this folder.

1. **Install WordPress:**
   The overrides file is in exercise 03's folder:

   ```bash
   helm -n wordpress install local-wp bitnami/wordpress --version 23.1.20 --create-namespace --values ../03-installing-wordpress-chart/wp-repo-overrides.yaml
   ```

   > **Bitnami images moved:** pin `--version 23.1.20` and pass the `bitnamilegacy` overrides file (see exercise 03). Without `--version`, Helm installs the latest chart (34.x), which uses different images.

   Watch the Pods until both are `Running` and ready, which takes about a minute, then stop the watch with `Ctrl+C`:

   ```bash
   kubectl -n wordpress get pods --watch
   ```

2. **Retrieve Secrets:**

   The chart generated random passwords and stored them in two Secrets, `local-wp-mariadb` and `local-wp-wordpress`. List the keys of the MariaDB one:

   ```bash
   kubectl -n wordpress describe secret local-wp-mariadb
   ```

   It holds `mariadb-password`, the password of the `bn_wordpress` user that WordPress connects with, and `mariadb-root-password`. Keep both values in shell variables for the comparison in step 5, not in a file in this public repository:

   ```bash
   OLD_DB_PW=$(kubectl -n wordpress get secret local-wp-mariadb -o jsonpath='{.data.mariadb-password}' | base64 -d)
   OLD_ROOT_PW=$(kubectl -n wordpress get secret local-wp-mariadb -o jsonpath='{.data.mariadb-root-password}' | base64 -d)
   ```

   The WordPress admin password is in `local-wp-wordpress`, under the key `wordpress-password` (see exercise 04).

3. **Uninstall WordPress:**

   ```bash
   helm -n wordpress uninstall local-wp
   kubectl -n wordpress get secret
   ```

   Helm deleted both Secrets along with the release record, so the second command finds no resources.

4. **Check PersistentVolumeClaims:**

   ```bash
   kubectl -n wordpress get pvc
   kubectl get pv
   ```

   `data-local-wp-mariadb-0` and its PersistentVolume are still there, while Helm deleted the WordPress PVC, `local-wp-wordpress` (see exercise 05 for why). The MariaDB data on that volume was initialized with the old passwords.

5. **Reinstall WordPress:**

   Run the same install command as in step 1. The chart generates new random passwords, so the new Secret no longer matches the values from step 2:

   ```bash
   helm -n wordpress install local-wp bitnami/wordpress --version 23.1.20 --create-namespace --values ../03-installing-wordpress-chart/wp-repo-overrides.yaml
   NEW_DB_PW=$(kubectl -n wordpress get secret local-wp-mariadb -o jsonpath='{.data.mariadb-password}' | base64 -d)
   NEW_ROOT_PW=$(kubectl -n wordpress get secret local-wp-mariadb -o jsonpath='{.data.mariadb-root-password}' | base64 -d)
   [ "$OLD_DB_PW" = "$NEW_DB_PW" ] && echo same || echo different
   [ "$OLD_ROOT_PW" = "$NEW_ROOT_PW" ] && echo same || echo different
   ```

   The MariaDB data on the reused PVC still expects the old passwords, while the new Secret holds new ones. After about three minutes, both Pods have restarted:

   ```bash
   kubectl -n wordpress get pods
   kubectl -n wordpress logs deploy/local-wp-wordpress
   kubectl -n wordpress logs local-wp-mariadb-0
   ```

   - WordPress never becomes ready. Its log stops at `Trying to connect to the database server`, and after a minute the container exits with `Could not connect to the database` and ends up in `CrashLoopBackOff`.
   - The MariaDB log rejects both logins: `Access denied for user 'bn_wordpress'` from WordPress, and `Access denied for user 'root'@'localhost'` from the Pod's own liveness probe, which runs `mariadb-admin status` with the new root password. The probe fails, so Kubernetes restarts MariaDB as well (`kubectl -n wordpress get events` shows `Container mariadb failed liveness probe, will be restarted`).

   > **Why the passwords don't change:** the WordPress chart's README says *"Once this chart is deployed, it is not possible to change the application's access credentials, such as usernames or passwords, using Helm. To change these application credentials after deployment, delete any persistent volumes (PVs) used by the chart and re-deploy it, or use the application's built-in administrative tools if available."*

6. **Clean Up:**

   Uninstall the release again, then delete the MariaDB PVC that Helm leaves behind:

   ```bash
   helm -n wordpress uninstall local-wp
   kubectl -n wordpress delete pvc data-local-wp-mariadb-0
   ```

   Confirm that nothing from the release is left, then delete the namespace and the shell variables:

   ```bash
   kubectl -n wordpress get all,pvc,secret
   kubectl get pv
   kubectl delete namespace wordpress
   unset OLD_DB_PW OLD_ROOT_PW NEW_DB_PW NEW_ROOT_PW
   ```

## Conclusion

In this exercise, we learned the importance of managing persistent data associated with Helm releases. By not cleaning up PersistentVolumeClaims, we can end up with old data that doesn't match a new install's configuration, and the application can't start. Values the chart generates at random, like these passwords, change with every new install, so they have to be stored, or set explicitly at install time, as exercises 07 and 08 do.
