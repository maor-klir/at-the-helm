# Ordering hooks with weights

## Overview

In this exercise, we'll add a second hook to the `helm-hooks` chart with a higher weight, watch Helm run the two hooks one after the other, and see that each hook's events and deletion policy apply to that hook alone.
Here's a quick summary of the main steps:

1. Add a second hook with weight `"1"`, and make the first hook take 10 seconds.
2. Upgrade, and compare the two Jobs' start and completion times.
3. Remove `pre-upgrade` from the second hook, and upgrade again.
4. Uninstall the release, and delete the Jobs it leaves behind.
5. See how Helm orders hooks with the same weight.

## Step-by-step guide

The chart in `helm-hooks/` is the end state of this exercise, and continues from exercise 04's chart.
To build it yourself, copy exercise 04's `helm-hooks` into an empty directory, and run the steps there. The release is `demo-hooks` in the namespace `helm-hooks`; install it first if it isn't there:

```bash
helm -n helm-hooks install demo-hooks helm-hooks --create-namespace
```

1. **Add a second hook:**

   Create `templates/hooks/second-hook.yaml`, a copy of `backup-db.yaml` with its own name, weight, and command. A second document after `---` in `backup-db.yaml` would work as well; a separate file is easier to find.

   ```yaml
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: "{{ include "helm-hooks.fullname" . }}-second"
     labels:
       {{- include "helm-hooks.labels" . | nindent 4 }}
     annotations:
       "helm.sh/hook": pre-upgrade,pre-delete,pre-rollback
       "helm.sh/hook-weight": "1"
       "helm.sh/hook-delete-policy": before-hook-creation
   spec:
     backoffLimit: 2
     template:
       metadata:
         labels:
           {{- include "helm-hooks.labels" . | nindent 8 }}
       spec:
         restartPolicy: Never
         containers:
           - name: dummy-backup-db
             image: "alpine:3.20.3"
             command: ["sh", "-c", "echo 'Executing some additional logic.'"]
   ```

   In `backup-db.yaml`, which keeps weight `"0"`, add a 10-second pause to the command:

   ```yaml
             command: ["sh", "-c", "echo 'Backing up some data.'; sleep 10;"]
   ```

2. **Upgrade, and watch the order:**

   In a second terminal, run `kubectl -n helm-hooks get jobs -w`, then upgrade:

   ```bash
   helm -n helm-hooks upgrade demo-hooks helm-hooks
   kubectl -n helm-hooks get jobs -o custom-columns='NAME:.metadata.name,CREATED:.metadata.creationTimestamp,COMPLETED:.status.completionTime'
   ```

   ```text
   NAME                              CREATED                COMPLETED
   demo-hooks-helm-hooks-backup-db   2026-11-27T10:10:07Z   2026-11-27T10:10:20Z
   demo-hooks-helm-hooks-second      2026-11-27T10:10:20Z   2026-11-27T10:10:23Z
   ```

   Weights are sorted in ascending order: `backup-db`, weight `"0"`, runs first, and Helm creates `second`, weight `"1"`, only once `backup-db` has completed. The upgrade itself continues after both, and takes 16.4 seconds.

3. **`before-hook-creation` works per hook:**

   Both Jobs are still there after the upgrade. The policy deletes a hook's previous resource before that same hook runs again; the hooks documentation describes it as *"Delete the previous resource before a new hook is launched"*, and running `second` doesn't delete the `backup-db` Job.

4. **Give each hook its own events:**

   The two hooks are independent: each has its own events, weight, and deletion policy. Remove `pre-upgrade` from `second-hook.yaml`:

   ```yaml
       "helm.sh/hook": pre-delete,pre-rollback
   ```

   After the next upgrade, only `backup-db` has a new Job:

   ```text
   NAME                              CREATED                COMPLETED
   demo-hooks-helm-hooks-backup-db   2026-11-27T10:10:31Z   2026-11-27T10:10:44Z
   demo-hooks-helm-hooks-second      2026-11-27T10:10:20Z   2026-11-27T10:10:23Z
   ```

5. **Uninstall the release:**

   ```bash
   helm -n helm-hooks uninstall demo-hooks
   ```

   Both hooks have the `pre-delete` event, so both run again, in weight order, before Helm removes the release:

   ```text
   NAME                              CREATED                COMPLETED
   demo-hooks-helm-hooks-backup-db   2026-11-27T10:10:49Z   2026-11-27T10:11:03Z
   demo-hooks-helm-hooks-second      2026-11-27T10:11:03Z   2026-11-27T10:11:07Z
   ```

   `helm -n helm-hooks list` is empty, but the two Jobs remain, since hooks aren't part of the release. Deleting them also deletes their Pods:

   ```bash
   kubectl -n helm-hooks delete job demo-hooks-helm-hooks-backup-db demo-hooks-helm-hooks-second
   ```

6. **Know how equal weights are ordered:**

   The hooks documentation says *"The library sorts hooks by weight (assigning a weight of 0 by default), by resource kind and finally by name in ascending order."* A test with two `pre-install` hooks of weight `"0"`, a Job named `aa-order-job` and a ConfigMap named `zz-order-cm`, showed a different order:

   ```text
   Job aa-order-job      created 2026-11-27T10:11:25Z  completed 2026-11-27T10:11:38Z
   ConfigMap zz-order-cm created 2026-11-27T10:11:38Z
   ```

   Ordered by kind, the ConfigMap would have come first. Helm's source sorts by weight, and breaks ties by the object's `metadata.name`, not the file name: both hooks were in one file, so the Job's name won.
   Whenever hooks depend on each other's order, give them explicit, different weights.

   Delete the namespace to finish:

   ```bash
   kubectl delete namespace helm-hooks
   ```

## Conclusion

In this exercise, we ran two hooks in weight order, saw that each hook keeps its own events and deletion policy, and found that hooks of equal weight run in name order.
Exercise 06 makes a hook fail.
