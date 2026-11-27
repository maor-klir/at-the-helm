# Working with hooks

## Overview

In this exercise, we'll create a chart with a hook, a Job that simulates a database backup before every upgrade, deletion, and rollback, and watch what Helm does with it during an install, upgrades, and an uninstall on k3d-argocd.
Here's a quick summary of the main steps:

1. Create the `helm-hooks` chart, and add the backup Job as a hook.
2. Install the chart, and upgrade it to run the hook.
3. Compare the hook deletion policies.
4. Print the hook's output with the `helm.sh/hook-output-log-policy` annotation.
5. Uninstall the release, and clean up what the hook leaves behind.

## Step-by-step guide

The chart in `helm-hooks/` is the end state of this exercise; the course created it with Helm 3's `helm create`.
To follow the steps, run them in an empty directory. The release is `demo-hooks` in the namespace `helm-hooks`.

1. **Create the chart:**

   ```bash
   helm create helm-hooks
   ```

   Helm 4's scaffold also has `templates/httproute.yaml`, `with` blocks in `deployment.yaml`, and an empty `charts/` directory; none of them affects this exercise.

2. **Add the hook:**

   Create `templates/hooks/backup-db.yaml`. The `hooks/` folder only keeps the files organized; Helm reads every template under `templates/`:

   ```yaml
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: "{{ include "helm-hooks.fullname" . }}-backup-db"
     labels:
       {{- include "helm-hooks.labels" . | nindent 4 }}
     annotations:
       "helm.sh/hook": pre-upgrade,pre-delete,pre-rollback
       "helm.sh/hook-weight": "0"
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
             command: ["sh", "-c", "echo 'Backing up some data.'"]
   ```

   | Annotation | Purpose | Value here |
   |---|---|---|
   | `helm.sh/hook` | marks the object as a hook, and names the events Helm runs it on; the only required one | `pre-upgrade`, `pre-delete`, and `pre-rollback`, not install, when there's no database to back up yet |
   | `helm.sh/hook-weight` | orders the hooks of one event, lowest first | `"0"`, the default, written out so the order is visible; a string, as Helm requires |
   | `helm.sh/hook-delete-policy` | decides when Helm deletes the hook's Job and Pods | `before-hook-creation`, the default: just before the hook runs again |

   `backoffLimit: 2` keeps a failing hook short. The Kubernetes Job documentation: *"The `.spec.backoffLimit` is set by default to 6"*, with *"an exponential back-off delay (10s, 20s, 40s ...) capped at ten minutes."*

   `helm template demo-hooks helm-hooks` renders the Job last, after the scaffold's objects; `--no-hooks` leaves it out.

   **The Pod's labels include the Service's selector:** `helm-hooks.labels` contains `app.kubernetes.io/name` and `app.kubernetes.io/instance`. During a test with a hook that sleeps 15 seconds, the Service's EndpointSlice listed the hook's Pod as a ready endpoint next to nginx, so the Service would send it traffic it can't serve. A real hook needs labels that the Service doesn't select.

3. **Install the chart:**

   ```bash
   helm -n helm-hooks install demo-hooks helm-hooks --create-namespace
   kubectl -n helm-hooks get jobs -w
   ```

   No Job appears: the hook has no `pre-install` or `post-install` event.

4. **Upgrade to run the hook:**

   In `values.yaml`, set the image tag, and upgrade:

   ```yaml
   image:
     tag: '1.27.0'
   ```

   ```bash
   helm -n helm-hooks upgrade demo-hooks helm-hooks
   ```

   The upgrade takes 8.4 seconds, against 0.4 for the install: the Job runs for 7 seconds, most of it pulling `alpine`, and Helm waits for it to complete before it updates the Deployment.
   The new nginx Pod is created only after the Job's completion. If the Job failed, the upgrade would fail without updating anything.

   ```text
   NAME                              STATUS     COMPLETIONS   DURATION   AGE
   demo-hooks-helm-hooks-backup-db   Complete   1/1           7s         7s
   ```

   The Job stays after the upgrade: `before-hook-creation` deletes it only before the next run.

5. **Compare the deletion policies:**

   | `helm.sh/hook-delete-policy` | After an upgrade |
   |---|---|
   | `before-hook-creation` | the completed Job and its Pod stay; `kubectl -n helm-hooks logs job/demo-hooks-helm-hooks-backup-db` prints `Backing up some data.` |
   | `before-hook-creation,hook-succeeded` | `kubectl -n helm-hooks get jobs` reports `No resources found` |
   | `hook-succeeded` alone | the upgrade succeeds, but the hook doesn't run |

   **Each run replaces the Job:** across one upgrade with `before-hook-creation`, the Job kept its name but got a new UID and creation time, `09:35:38Z` before and `09:36:05Z` after.

   **`hook-succeeded` alone skips the hook in Helm 4:** the completed Job from the previous run is still there, and Helm 4 creates hook resources with server-side apply, which updates the existing Job in place instead of creating a new one.
   Helm then finds the Job complete, counts the hook as succeeded, and deletes it: the upgrade's events show no new Pod. With `--server-side=false`, the upgrade fails as it did in Helm 3:

   ```text
   Error: UPGRADE FAILED: pre-upgrade hooks failed: warning: Hook pre-upgrade helm-hooks/templates/hooks/backup-db.yaml failed: jobs.batch "demo-hooks-helm-hooks-backup-db" already exists
   ```

   Keep `before-hook-creation` in the policy whenever the hook's name doesn't change between runs.

6. **Print the hook's output:**

   A fourth hook annotation, `helm.sh/hook-output-log-policy`, takes the values `hook-succeeded` and `hook-failed`. Helm 3.18 added it, and the hooks documentation doesn't list it yet; Helm reads it for Job and Pod hooks. Add it to the Job's annotations:

   ```yaml
       "helm.sh/hook-output-log-policy": hook-succeeded
   ```

   The next upgrade prints the hook's log before Helm's own output:

   ```text
   level=INFO msg="Backing up some data."
   Release "demo-hooks" has been upgraded. Happy Helming!
   ```

   With `hook-failed`, the log appears only when the hook fails, where it's most useful. The chart in this folder doesn't set the annotation.

7. **Uninstall the release:**

   ```bash
   helm -n helm-hooks uninstall demo-hooks
   kubectl -n helm-hooks get all
   ```

   The `pre-delete` hook runs first, and its Job and Pod survive the uninstall:

   ```text
   NAME                                        READY   STATUS      RESTARTS   AGE
   pod/demo-hooks-helm-hooks-backup-db-5xp8m   0/1     Completed   0          25s

   NAME                                        STATUS     COMPLETIONS   DURATION   AGE
   job.batch/demo-hooks-helm-hooks-backup-db   Complete   1/1           20s        26s
   ```

   The hooks documentation explains: *"The resources that a hook creates are currently not tracked or managed as part of the release."*
   `helm uninstall` runs the hooks stored in the release, not the ones in the chart's directory: a `sleep 15` removed from the local chart before the uninstall still ran.

   Delete the namespace to remove the leftover Job:

   ```bash
   kubectl delete namespace helm-hooks
   ```

## Conclusion

In this exercise, we ran a Job as a `pre-upgrade` and `pre-delete` hook, saw Helm wait for it, compared the deletion policies, and found that in Helm 4 a hook with only `hook-succeeded` is skipped instead of failing.
Exercise 05 orders several hooks with weights.
