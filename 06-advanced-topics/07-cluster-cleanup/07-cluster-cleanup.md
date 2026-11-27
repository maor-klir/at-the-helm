# Cleaning up after hooks

## Overview

In this exercise, we'll remove the `demo-hooks` release from exercises 04–06, and the hook Jobs that `helm uninstall` leaves behind.
Here's a quick summary of the main steps:

1. Uninstall the release.
2. Find the hook Jobs and Pods that remain.
3. Delete them, or the whole namespace.

## Step-by-step guide

This exercise has no chart of its own; it cleans up after exercise 06's `demo-hooks` release in the namespace `helm-hooks`.

1. **Uninstall the release:**

   ```bash
   helm -n helm-hooks uninstall demo-hooks
   ```

   The uninstall runs the `pre-delete` hook, `second`, and then removes the release's own objects: the Deployment, the Service, and the ServiceAccount.

2. **Find what remains:**

   ```bash
   kubectl -n helm-hooks get jobs,pods
   ```

   The hook Jobs are still there, with their Pods: `backup-db` from the last upgrade and `second` from the uninstall. The hooks documentation explains why: *"The resources that a hook creates are currently not tracked or managed as part of the release."*

3. **Delete the Jobs:**

   ```bash
   kubectl -n helm-hooks delete job demo-hooks-helm-hooks-backup-db demo-hooks-helm-hooks-second
   kubectl -n helm-hooks get jobs,pods
   ```

   ```text
   job.batch "demo-hooks-helm-hooks-backup-db" deleted from helm-hooks namespace
   job.batch "demo-hooks-helm-hooks-second" deleted from helm-hooks namespace
   No resources found in helm-hooks namespace.
   ```

   Deleting a Job also deletes its Pods. The labs used their own namespace, so `kubectl delete namespace helm-hooks` removes everything at once, the Jobs included.

   **Hooks can clean up after themselves:** the hooks documentation names two ways, *"either add a custom `helm.sh/hook-delete-policy` annotation to the hook template file, or set the time to live (TTL) field of a Job resource"*.
   `hook-succeeded` and `hook-failed` delete the Job as soon as the hook ends (exercise 04). A Job's `.spec.ttlSecondsAfterFinished` lets Kubernetes delete it some time after it has finished, which leaves time to read its logs.

## Conclusion

In this exercise, we removed the `demo-hooks` release and the hook Jobs it left behind, and saw the two ways a hook can remove its own Job.
Exercise 08 starts the library charts part of the section.
