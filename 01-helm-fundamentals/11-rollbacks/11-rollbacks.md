# Rollbacks in Helm

## Overview

This exercise will dive into the concept of rollbacks in Helm, particularly focusing on how to revert changes made during a Helm upgrade that didn't go as planned.
A good example is an upgradeded WordPress release that did not go as planned, we'll learn how to roll back to the last functional version smoothly.

A quick summary of the main steps:

1. Upgrade your Helm release and intentionally set a non-existent image tag.
2. Verify the status of your Pods to see any errors.
3. Check the Helm history for the release to confirm the problematic upgrade was recorded.
4. Use the `helm rollback` command to revert to the last successful version.
5. Check what the rollback left behind.

## Step-by-Step Guide

The release `local-wp` from exercise 10 should be at revision 3, on chart 23.1.28.

1. **Perform Helm Upgrade:**

   Use `helm upgrade` on your release while setting a non-existent image tag.

   ```bash
   helm -n wordpress upgrade local-wp bitnami/wordpress --version 23.1.28 --reuse-values --set image.tag=non-existent
   ```

   > **Bitnami images moved:** keep `--reuse-values` and `--version 23.1.28`.
   > Without `--reuse-values`, `--set` replaces all earlier values, so the `bitnamilegacy` overrides are dropped and MariaDB fails along with WordPress.
   > Without `--version`, Helm upgrades to the latest chart (34.x).

   `--reuse-values` is safe here because the chart version doesn't change, so the old chart's defaults are the same as the new ones. `image.tag` changes only the WordPress image; MariaDB's would be `mariadb.image.tag`.

   > **Why Helm reports success:** without `--wait`, Helm 4 waits only for hooks.
   > The `helm upgrade` reference says "Default when flag is omitted: 'hookOnly'", so the release is marked `deployed` even though the new Pod can't start.
   > With `--rollback-on-failure` (exercise 12), the same upgrade would wait for the Pods and roll back on its own.

2. **Check Pods Status:**

   ```bash
   kubectl -n wordpress get pods
   kubectl -n wordpress describe pod <new-pod-name>
   ```

   The two existing Pods keep running. The new Pod fails before its main container: the chart's `prepare-base-dir` init container uses the same WordPress image, so the Pod goes to `Init:ErrImagePull`, then `Init:ImagePullBackOff`.
   `describe` shows `Failed to pull image "docker.io/bitnamilegacy/wordpress:non-existent"` for `spec.initContainers{prepare-base-dir}`.

3. **View Helm History:**

   ```bash
   helm -n wordpress history local-wp
   ```

   Revision 4 is `deployed`, and revision 3 is `superseded`.

4. **Rollback to Previous Revision:**

   ```bash
   helm -n wordpress rollback local-wp 3
   helm -n wordpress history local-wp
   helm -n wordpress get values local-wp
   kubectl -n wordpress get secret
   ```

   The rollback writes revision 5, with the description `Rollback to 3`.
   The values no longer contain `image.tag`, and the release records now go up to `sh.helm.release.v1.local-wp.v5`.
   The revision number can be left out: the `helm rollback` reference says "If this argument is omitted or set to 0, it will roll back to the previous release."

5. **Check What the Rollback Left Behind:**

   ```bash
   kubectl -n wordpress get rs
   ```

   The ReplicaSet with the broken image is now at 0 Pods, next to older ones. These aren't leftovers of the failed upgrade: the Deployment owns them, they aren't in Helm's manifest, and Kubernetes keeps them on purpose.

   The Kubernetes Deployment docs say "You can set `.spec.revisionHistoryLimit` field in a Deployment to specify how many old ReplicaSets for this Deployment you want to retain. The rest will be garbage-collected in the background. By default, it is 10."
   `kubectl rollout undo` uses them, so deleting them is optional:

   ```bash
   kubectl -n wordpress delete rs <replicaset-name>
   ```

   Helm's rollback does delete Helm objects that the failed revision added and the target revision doesn't have: it applies revision 3's manifest and removes whatever is in the current manifest but not in the target.

## Conclusion

We learned the importance of rollbacks in Helm, especially when facing issues after an upgrade.
A rollback removes the objects Helm created in the failed revision, while the Deployment keeps its old ReplicaSets, up to its `revisionHistoryLimit`.
