#helm #kubernetes

# Rolling back releases

When an upgrade breaks a release, Helm can return it to an earlier revision, by hand with `helm rollback` or automatically with `--rollback-on-failure`.
Either way, the rollback is recorded as a new revision.
Objects that Kubernetes created on its own, such as a Deployment's ReplicaSets, are not part of it.

## A broken upgrade can still be `deployed`

An upgrade that sets `image.tag=non-existent` on our WordPress release finishes with `STATUS: deployed`.
Helm 4 waits only for hooks unless told otherwise; the `helm upgrade` reference describes `--wait` as *"wait until resources are ready (up to --timeout). Use '--wait' alone for 'watcher' strategy, or specify one of: 'watcher', 'hookOnly', 'legacy'. Default when flag is omitted: 'hookOnly'."*

**The new Pod fails in its init container:** the chart's `prepare-base-dir` init container uses the same WordPress image.
The Pod goes to `Init:ErrImagePull`, then `Init:ImagePullBackOff`, and `kubectl describe pod` reports `Failed to pull image "docker.io/bitnamilegacy/wordpress:non-existent"` for `spec.initContainers{prepare-base-dir}`.

**The old Pods keep serving:** the Deployment's strategy is a plain `RollingUpdate`, so the Kubernetes defaults apply.

The Deployment documentation sets both limits to 25%; for `maxUnavailable` *"The absolute number is calculated from percentage by rounding down"*, and for `maxSurge` *"The absolute number is calculated from the percentage by rounding up."*
With two Pods, that is zero unavailable and one extra, so the rollout adds one new Pod and removes no old one until it is ready.

## Rolling back by hand

The `helm rollback` reference: *"This command rolls back a release to a previous revision."*
The revision number is optional: *"If this argument is omitted or set to 0, it will roll back to the previous release."*

```bash
helm -n wordpress rollback local-wp 3
```

The rollback wrote revision 5 with the description `Rollback to 3`, so the history keeps the broken revision 4 (see **01 - The role of Helm in Kubernetes**).
`helm get values` on revision 5 no longer contains `image.tag`, and the broken Pod was removed while the two old Pods stayed.

**Only revisions still in the history can be targeted:** `--history-max` (default 10) deletes the oldest records as new revisions are written (see **14 - Upgrading releases**), so neither a rollback nor `helm get values --revision` can reach a revision that has been pruned.

**A rollback reuses the stored manifest:** Helm's template guide says *"`helm uninstall` and `helm rollback` do not render templates, so `lookup` is not called by these commands."*

It applies revision 3's manifest with the release's apply method, server-side apply for ours.
The `--server-side` flag defaults to `auto`, which, the `helm rollback` reference says, *"defaults the value from the previous chart release's method"*.

**Helm deletes what it added in the broken revision:** in Helm's source, the rollback applies the target manifest through the same update function as an upgrade, which deletes every object in the current manifest that the target manifest doesn't have.
Our broken revision added no objects, so nothing was deleted.

## What a rollback leaves: the Deployment's ReplicaSets

After the rollback, `kubectl get rs` still lists a ReplicaSet with the broken image, at 0 Pods, next to the one from chart 23.1.20.
Both are owned by the Deployment, and neither is in Helm's manifest, so neither a rollback nor `--cleanup-on-fail` touches them.

The Deployment keeps them on purpose.
The Kubernetes Deployment documentation: *"You can set `.spec.revisionHistoryLimit` field in a Deployment to specify how many old ReplicaSets for this Deployment you want to retain. The rest will be garbage-collected in the background. By default, it is 10."*
Deleting them by hand is optional.

**The rollback didn't create a ReplicaSet:** revision 3's Pod template matched an existing ReplicaSet, so the Deployment scaled that one back to two Pods.
`kubectl rollout history` then listed the Deployment's own revisions 1, 3, and 4, which have nothing to do with Helm's revisions 1 to 5.

## Rolling back automatically

**`--rollback-on-failure` is Helm 4's name for `--atomic`:** the old name still works, prints *"Flag --atomic has been deprecated, use --rollback-on-failure instead"*, and no longer appears in `helm upgrade --help`.
`--force` was renamed the same way, to `--force-replace`.

The `helm upgrade` reference describes the flag:

> *"if set, Helm will rollback the upgrade to previous success release upon failure. The --wait flag will be defaulted to "watcher" if --rollback-on-failure is set"*

**Three more flags shape the failure:** each has its own entry in the `helm upgrade` reference.

| Flag | Reference description |
|---|---|
| `--timeout` | *"time to wait for any individual Kubernetes operation (like Jobs for hooks) (default 5m0s)"* |
| `--cleanup-on-fail` | *"allow deletion of new resources created in this upgrade when upgrade fails"* |
| `--debug` | *"enable verbose output"* |

`--cleanup-on-fail` only covers objects that are new in the failed revision, and our broken upgrade adds none.

The same broken upgrade, guarded:

```bash
helm -n wordpress upgrade local-wp bitnami/wordpress --version 23.1.28 \
  --reuse-values --values custom-values.yaml \
  --set image.tag=non-existent \
  --rollback-on-failure --cleanup-on-fail --debug --timeout 2m
```

`--set image.tag` wins over the values file through precedence, not through its position on the command line (see **13 - Overriding chart values**).

**The debug output shows the watcher at work:** Helm applies all 14 objects with server-side apply (`Patched resource`), then logs `waiting for resources count=14 timeout=2m0s`.
It repeats `waiting for resource … kind=Deployment expectedStatus=Current actualStatus=InProgress` until the timeout.

After 125 seconds the command exits with code 1:

```text
Error: UPGRADE FAILED: release local-wp failed, and has been rolled back due to rollback-on-failure being set: resource Deployment/wordpress/local-wp-wordpress not ready. status: InProgress, message: Updated: 1/2
context deadline exceeded
```

**The failed revision stays in the history:** revision 7 is `failed`, with the description `Upgrade "local-wp" failed: resource Deployment/wordpress/local-wp-wordpress not ready…`, and revision 8 is `deployed`, with `Rollback to 6`.
`helm get values local-wp --revision 7` still shows `tag: non-existent`, which is where to look before trying the upgrade again.

## Verify

The unguarded broken upgrade is `deployed`, and its Pod fails in the init container:

```bash
helm -n wordpress upgrade local-wp bitnami/wordpress --version 23.1.28 --reuse-values --set image.tag=non-existent
kubectl -n wordpress get pods                       # one new Pod in Init:ImagePullBackOff, two old Pods Running
kubectl -n wordpress describe pod <new-pod-name>    # Failed to pull image … for spec.initContainers{prepare-base-dir}
```

The manual rollback, its revision, and what it leaves:

```bash
helm -n wordpress rollback local-wp 3
helm -n wordpress history local-wp                  # Rollback to 3
kubectl -n wordpress get rs                         # the broken ReplicaSet at 0, owned by the Deployment
kubectl -n wordpress rollout history deploy/local-wp-wordpress
```

After the guarded upgrade, the failed revision and the automatic rollback:

```bash
helm -n wordpress history local-wp                  # failed, then Rollback to 6
helm -n wordpress get values local-wp --revision 7  # tag: non-existent
```
