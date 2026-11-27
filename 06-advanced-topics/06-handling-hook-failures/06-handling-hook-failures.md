# Handling hook failures

## Overview

In this exercise, we'll make the `backup-db` hook fail, first as a `pre-upgrade` hook and then as a `post-upgrade` hook, and see what each failure leaves in the cluster and in the release history. Then we'll let Helm roll back automatically with `--rollback-on-failure`.
Here's a quick summary of the main steps:

1. Make the `pre-upgrade` hook fail, and upgrade.
2. Upgrade with a new image tag while the hook still fails.
3. Upgrade successfully once, to have a good revision.
4. Move the failing hook to `post-upgrade`, and upgrade.
5. Upgrade with `--rollback-on-failure`.

## Step-by-step guide

The chart in `helm-hooks/` is the end state of this exercise, and continues from exercise 05's chart: its `backup-db` hook is a `post-upgrade` hook that always fails, so every upgrade of it fails on purpose.
To follow the steps, copy exercise 05's `helm-hooks` into an empty directory. The release is `demo-hooks` in the namespace `helm-hooks`.

In `templates/hooks/backup-db.yaml`, keep only the `pre-upgrade` event, and install the release with the image tag `1.27.0` from exercise 04:

```yaml
    "helm.sh/hook": pre-upgrade
```

```bash
helm -n helm-hooks install demo-hooks helm-hooks --create-namespace
```

1. **Make the `pre-upgrade` hook fail:**

   Replace the hook's command with one that exits with code 1:

   ```yaml
             command: ["sh", "-c", "echo 'I will fail.'; exit 1;"]
   ```

   ```bash
   helm -n helm-hooks upgrade demo-hooks helm-hooks
   ```

   The Job retries twice, as `backoffLimit: 2` allows, and the upgrade fails after 34 seconds:

   ```text
   Error: UPGRADE FAILED: pre-upgrade hooks failed: resource Job/helm-hooks/demo-hooks-helm-hooks-backup-db not ready. status: Failed, message: Job Failed. failed: 3/1
   ```

   `helm -n helm-hooks history demo-hooks` shows revision 2 as `failed`, with the same message. The three failed Pods are kept, so `kubectl -n helm-hooks logs` can still read them, and nginx still runs its Pod from the install.

2. **Upgrade with a new image tag:**

   Set `image.tag: '1.27.1'` in `values.yaml`, and upgrade again. `before-hook-creation` deletes the failed Job and its three Pods before the new attempt.

   The upgrade fails the same way, and nginx is still the same Pod, created at the install, with `nginx:1.27.0`. A failed pre-hook stops the operation before Helm changes any of the release's resources. The other operations' pre-hooks run at the same point, before any change, as the hooks documentation's install lifecycle shows.

3. **Upgrade successfully once:**

   Set `image.tag: '1.16.0'`, the chart's `appVersion`, and let the hook succeed:

   ```yaml
             command: ["sh", "-c", "echo 'I will not fail.'; exit 0;"]
   ```

   The upgrade succeeds as revision 4, and nginx runs `nginx:1.16.0`.

4. **Make a `post-upgrade` hook fail:**

   Change the hook's event, and make it fail again:

   ```yaml
       "helm.sh/hook": post-upgrade
   ```

   ```yaml
             command: ["sh", "-c", "echo 'I will fail.'; exit 1;"]
   ```

   Set `image.tag: '1.27.0'`, and upgrade. Eight seconds in, while the hook is still retrying, nginx already runs a new Pod with `nginx:1.27.0`.
   The upgrade then fails with `post-upgrade hooks failed`, and the new Pod stays: Helm doesn't revert the resources it has already updated. Revision 5 is `failed`, while `helm history` still lists revision 4 as `deployed`.

5. **Roll back on failure:**

   Set `image.tag: '1.27.1'`, and upgrade with `--rollback-on-failure`, Helm 4's name for Helm 3's `--atomic`. `--atomic` still works, with the warning `Flag --atomic has been deprecated, use --rollback-on-failure instead`.

   ```bash
   helm -n helm-hooks upgrade demo-hooks helm-hooks --rollback-on-failure
   ```

   ```text
   Error: UPGRADE FAILED: release demo-hooks failed, and has been rolled back due to rollback-on-failure being set: post-upgrade hooks failed: resource Job/helm-hooks/demo-hooks-helm-hooks-backup-db not ready. status: Failed, message: Job Failed. failed: 3/1
   ```

   ```bash
   helm -n helm-hooks history demo-hooks
   ```

   Without the `UPDATED`, `CHART`, and `APP VERSION` columns, and with the long descriptions shortened:

   ```text
   REVISION  STATUS      DESCRIPTION
   1         superseded  Install complete
   2         failed      Upgrade "demo-hooks" failed: pre-upgrade hooks failed: …
   3         failed      Upgrade "demo-hooks" failed: pre-upgrade hooks failed: …
   4         superseded  Upgrade complete
   5         failed      Upgrade "demo-hooks" failed: post-upgrade hooks failed: …
   6         failed      Upgrade "demo-hooks" failed: post-upgrade hooks failed: …
   7         deployed    Rollback to 4
   ```

   Helm rolled back to revision 4, the last successful one, not to the failed revision 5, so nginx runs `nginx:1.16.0` again. The rollback also ran the `second` hook, whose events include `pre-rollback`.
   The flag's help explains how it waits: *"The --wait flag will be defaulted to "watcher" if --rollback-on-failure is set"*. The command took 60 seconds.

   **Print a failing hook's output:** with `"helm.sh/hook-output-log-policy": hook-failed` added to the hook's annotations (see exercise 04), a failed upgrade prints the hook's output once for each failed attempt, before the error:

   ```text
   level=INFO msg="I will fail."
   level=INFO msg="I will fail."
   level=INFO msg="I will fail."
   ```

   To finish, set `image.tag` back to `'1.27.0'`, as the chart in this folder has it, and delete the namespace:

   ```bash
   kubectl delete namespace helm-hooks
   ```

## Conclusion

In this exercise, we saw that a failed pre-hook stops an upgrade before any change, that a failed post-hook leaves the upgraded resources in place, and that `--rollback-on-failure` rolls back to the last successful revision.
Exercise 07 cleans up the cluster.
