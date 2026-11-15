# Uninstalling a Helm release

## Overview

In this exercise, we'll uninstall a Helm release and check what it leaves behind in the cluster. Here's a quick summary of the main steps:

1. List the installed Helm releases using `helm list`.
2. Uninstall the desired release with `helm uninstall <release-name>`.
3. Check for any remaining resources, such as Services and Pods, and remove those if necessary.
4. Look for any PersistentVolumeClaims (PVCs) that need to be deleted.
5. Confirm that no PersistentVolumeClaims or PersistentVolumes are left, and delete the namespace.

## Step-by-step guide

1. **List installed releases:**

   The release `local-wp` lives in the `wordpress` namespace, so pass `-n wordpress` (or use `-A` to list releases in all namespaces):

   ```bash
   helm -n wordpress list
   ```

2. **Uninstall the release:**

   ```bash
   helm -n wordpress uninstall local-wp
   ```

   This also deletes the release history, the `sh.helm.release.v1.local-wp.v*` Secrets. Add `--keep-history` to keep them.

3. **Check for remaining resources:**

   ```bash
   kubectl -n wordpress get pods,svc
   ```

4. **Stop the port-forward:**

   Exercise 03 uses a background `kubectl port-forward` instead of `kubectl expose`, so no hand-made Service is left to delete. The forward points at a Service that no longer exists, so stop it:

   ```bash
   kill %1                              # in the shell that started it
   pkill -f 'port-forward.*9090'        # from any shell
   ```

5. **Handle PersistentVolumeClaims:**

   ```bash
   kubectl -n wordpress get pvc
   ```

   `data-local-wp-mariadb-0` is still there. MariaDB is a StatefulSet, and its PVC comes from the StatefulSet's `volumeClaimTemplates`, not from the chart's templates, so Helm never managed it.
   Kubernetes keeps StatefulSet PVCs when the StatefulSet is deleted (`persistentVolumeClaimRetentionPolicy` defaults to `Retain`).

   The WordPress PVC, `local-wp-wordpress`, is one of the chart's templates, so Helm deletes it with the release.

   Delete the MariaDB PVC:

   ```bash
   kubectl -n wordpress delete pvc data-local-wp-mariadb-0
   ```

   > **k3d-argocd cluster:** the StorageClass is k3s's `local-path`, whose reclaim policy is `Delete`, so deleting the PVC also deletes its PersistentVolume.
   > `kubectl get pv` shows each volume's `RECLAIM POLICY` directly.
   > With `Retain`, the PersistentVolume would stay and need deleting by hand.

6. **Confirm deletion of resources:**

   ```bash
   kubectl -n wordpress get pvc
   kubectl get pv
   ```

   Helm doesn't delete the `wordpress` namespace that `--create-namespace` created, because the namespace isn't part of the release. Delete it once it's empty:

   ```bash
   kubectl delete namespace wordpress
   ```

## Conclusion

After uninstalling a release, check for lingering resources, particularly PersistentVolumeClaims and the PersistentVolumes behind them.
