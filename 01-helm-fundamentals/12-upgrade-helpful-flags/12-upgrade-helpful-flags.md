# Helm Upgrade: Helpful Flags and Best Practices

## Overview

In this guide, we will explore some important flags you can use with the `helm upgrade` command to ensure a smooth upgrade process in your Kubernetes deployments. Our focus is on preventing issues during upgrades by using specific options that help manage resources effectively.

Before we dive into the step-by-step guide, let's summarize what you'll be implementing in this exercise. You'll try to successfully upgrade a Helm release while incorporating helpful flags to manage potential failures. Here’s a quick rundown of what you should aim to do:

1. Identify the Service type you need to update for your deployment (change from LoadBalancer to NodePort).
2. Modify your custom values YAML file accordingly.
3. Execute the Helm upgrade command with the relevant flags to handle potential errors.
4. Validate the upgrade and check Helm's revision history to ensure everything is functioning correctly.
5. Uninstall the release and clean up what it leaves behind.

## Step-by-Step Guide

Run the commands from this folder. The release `local-wp` from exercise 11 should be at revision 5, on chart 23.1.28.

1. **Update Service Type:**
   `custom-values.yaml` in this folder is exercise 09's file with one more block:

   ```yaml
   service:
     type: NodePort
   ```

   > **k3d-argocd cluster:** k3s's ServiceLB gives a `LoadBalancer` Service external IPs on the k3d Docker network. Switching to `NodePort` is a valid configuration change for a first, successful upgrade. Neither type is reachable from the laptop, so the port-forward from exercise 03 stays the way in.

2. **Run a Successful Upgrade:**

   ```bash
   helm -n wordpress upgrade local-wp bitnami/wordpress --version 23.1.28 --reuse-values --values custom-values.yaml
   kubectl -n wordpress get pods,svc
   helm -n wordpress history local-wp
   ```

   The Pods are unchanged, `local-wp-wordpress` is now a `NodePort` Service, and revision 6 is `deployed`.

3. **Prepare the Failing Upgrade:**
   The same upgrade with the non-existent image tag from exercise 11, guarded by four flags:

   ```bash
   helm -n wordpress upgrade local-wp bitnami/wordpress --version 23.1.28 \
     --reuse-values --values custom-values.yaml \
     --set image.tag=non-existent \
     --rollback-on-failure --cleanup-on-fail --debug --timeout 2m
   ```

   > **Bitnami images moved:** pin `--version 23.1.28`. Without it, Helm upgrades to the latest chart (34.x). `--reuse-values` keeps the `bitnamilegacy` overrides from the install.

   - `--rollback-on-failure` is the Helm 4 name of `--atomic`. The old name still works but prints "Flag --atomic has been deprecated, use --rollback-on-failure instead". The `helm upgrade` reference: "if set, Helm will rollback the upgrade to previous success release upon failure. The --wait flag will be defaulted to "watcher" if --rollback-on-failure is set". Without `--wait`, Helm would wait only for hooks and mark the broken release `deployed`, as in exercise 11.
   - `--cleanup-on-fail`: "allow deletion of new resources created in this upgrade when upgrade fails". It covers objects that are new in this revision; this upgrade adds none.
   - `--debug` prints Helm's progress while it waits.
   - `--timeout 2m` shortens the default of `5m0s`; the wait for the Pods counts against it.

   `--set image.tag` wins over the values file because `--set` values are merged into `--values` with higher precedence, whatever their order on the command line.

4. **Run the Upgrade Command:**
   Run the command from step 3. The debug output shows Helm applying all 14 objects with server-side apply (`Patched resource`), then waiting: `waiting for resource … kind=Deployment expectedStatus=Current actualStatus=InProgress`. After two minutes, Helm gives up and rolls back:

   ```text
   Error: UPGRADE FAILED: release local-wp failed, and has been rolled back due to rollback-on-failure being set: resource Deployment/wordpress/local-wp-wordpress not ready. status: InProgress, message: Updated: 1/2
   context deadline exceeded
   ```

5. **Review the Results:**

   ```bash
   kubectl -n wordpress get pods,svc
   helm -n wordpress history local-wp
   helm -n wordpress get values local-wp --revision 7
   helm -n wordpress get values local-wp --revision 8
   ```

   Two WordPress Pods are running. Revision 7 is `failed`, with the description `Upgrade "local-wp" failed: …`, and revision 8 is `deployed`, with `Rollback to 6`. Revision 7's values still show `image.tag: non-existent`, which is where to look before fixing an upgrade; revision 8's don't.

6. **Check Leftover ReplicaSets:**

   ```bash
   kubectl -n wordpress get rs
   ```

   The ReplicaSet with the broken image is at 0 Pods. As in exercise 11, the Deployment owns it and keeps it under its `revisionHistoryLimit` (10), so `--cleanup-on-fail` doesn't touch it. Deleting it is optional: `kubectl -n wordpress delete rs <replicaset-name>`.

7. **Clean Up Resources:**

   ```bash
   helm -n wordpress uninstall local-wp
   kubectl -n wordpress delete pvc data-local-wp-mariadb-0
   kubectl delete namespace wordpress
   kubectl get pv
   ```

   Deleting the namespace also removes the `custom-wp-credentials` Secret from exercise 08. The `local-path` StorageClass reclaims with `Delete`, so the PersistentVolumes go with their PVCs, and `kubectl get pv` finds none. Stop the port-forward too, if one is still running: `kill %1`.

## Conclusion

In this guide, we learned how to effectively utilize Helm upgrade flags to streamline the deployment process and make it more resilient to failures. By leveraging options like `--rollback-on-failure` and `--cleanup-on-fail`, you can maintain a clean state in your Kubernetes environment, even when things don't go according to plan.
