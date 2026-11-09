# Upgrading Helm Releases: A Practical Guide

## Overview

In this exercise, we will focus on upgrading Helm releases effectively.
As our applications evolve, we often need to modify or update our configurations without the hassle of uninstalling and reinstalling Helm releases.
Instead, we can make use of the `helm upgrade` command to get the job done smoothly.

Before diving into the step-by-step guide, here’s a quick summary of the main steps you should try to implement on your own:

1. Enable auto-scaling in your `custom-values.yaml` configuration.
2. Set the minimum and maximum replicas for the auto-scaling feature.
3. Run the `helm upgrade` command with necessary parameters and flags.
4. Verify the upgrade and check the changes made to your application.

## Step-by-Step Guide

Run the commands from this folder. The release `local-wp` from exercise 08 should still be installed.

1. **Check the Metrics Server:**

   The HorizontalPodAutoscaler needs Pod metrics:

   ```bash
   kubectl -n kube-system get deploy metrics-server
   kubectl -n wordpress top pods
   ```

   > **k3d-argocd cluster:** metrics-server is already installed. `kubectl top pods` returns CPU and memory for every Pod once it's working.

2. **Modify Your `custom-values.yaml`:**

   `custom-values.yaml` in this folder is exercise 08's file with `replicaCount: 3` replaced by autoscaling:

   ```yaml
   autoscaling:
     enabled: true
     minReplicas: 2
     maxReplicas: 10
   ```

   Values the file doesn't set keep the chart's defaults, so `targetCPU` and `targetMemory` stay at 50.

3. **Run the Upgrade Command:**

   ```bash
   helm -n wordpress upgrade local-wp bitnami/wordpress --version 23.1.20 --reuse-values --values custom-values.yaml
   ```

   `--version 23.1.20` keeps the installed chart version; without it, Helm upgrades to the latest chart (34.x).
   `--reuse-values` takes revision 1's user-supplied values and merges this file on top, so `replicaCount: 3` stays in the release's values even though the file no longer sets it.

   > **The MariaDB passwords:** the generated MariaDB passwords survive the upgrade because the chart reads them back from the existing `local-wp-mariadb` Secret (the `common.secrets.passwords.manage` helper uses `lookup`), not because of `--reuse-values`.
   > `--reuse-values` only carries over values that were supplied with `--values` or `--set`.

4. **Observe the Upgrade Process:**

   ```bash
   kubectl -n wordpress get pods --watch
   kubectl -n wordpress get hpa
   ```

   The WordPress Pods end at two, the HorizontalPodAutoscaler's minimum.

   On the way, the Deployment briefly drops to one: the upgrade stops rendering `replicas:`, so Helm's server-side apply gives the field up and it falls back to its default of 1.
   The HorizontalPodAutoscaler then raises it to 2. `kubectl -n wordpress get events` shows `Scaled down replica set … from 3 to 1`, then `New size: 2; reason: Current number of replicas below Spec.MinReplicas`.

   > **Why `replicaCount: 3` has no effect:** the chart's Deployment template renders `replicas:` only when `autoscaling.enabled` is false. With autoscaling on, the HorizontalPodAutoscaler sets the number of Pods.

5. **Validate Configurations:**

   ```bash
   helm -n wordpress get values local-wp
   helm -n wordpress get values local-wp --revision 1
   ```

   The current values merge both revisions: `replicaCount: 3` from revision 1 next to the new `autoscaling` block. `--revision 1` shows the values as they were at the install.

6. **Check History and Secrets:**

   ```bash
   helm -n wordpress history local-wp
   kubectl -n wordpress get secret
   ```

   Revision 1 is `superseded` and revision 2 is `deployed`, and each revision has its own release record, `sh.helm.release.v1.local-wp.v1` and `sh.helm.release.v1.local-wp.v2`.
   `--history-max` on `helm upgrade` limits how many revisions Helm keeps: *"limit the maximum number of revisions saved per release. Use 0 for no limit (default 10)"*.

## Conclusion

In this guide, we tackled how to upgrade Helm releases smoothly using the `helm upgrade` command, without any unnecessary reinstalls. We also learned the significance of managing configurations effectively to get the desired outcomes.
