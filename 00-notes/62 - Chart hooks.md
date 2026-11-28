#helm #kubernetes #hooks

# Chart hooks

A hook is a template whose object Helm creates at a fixed point of a release's lifecycle, before or after an install, upgrade, rollback, or uninstall, instead of together with the release's other objects.
The hooks documentation: *"Hooks work like regular templates, but they have special annotations that cause Helm to utilize them differently."*

A typical hook is a Job that backs up a database before an upgrade, or loads data after an install.

## The test chart

The results below come from one chart on a k3s cluster: `helm-hooks`, created with `helm create`, whose Deployment runs nginx, installed as the release `demo-hooks`.
Two Jobs in its `templates/hooks/` are hooks; both run `alpine` with `backoffLimit: 2`, so a failing Job gets three attempts:

| Hook | Job name | Command | Weight |
|---|---|---|---|
| `backup-db` | `demo-hooks-helm-hooks-backup-db` | prints `Backing up some data.`, or exits with code 1 where a result says it fails | `"0"` |
| `second` | `demo-hooks-helm-hooks-second` | prints `Executing some additional logic.` | `"1"` |

Each Job's Pod template copies the Deployment's labels.
Each result below names the events and policies the hooks had for it.

## The events

| Event | Runs |
|---|---|
| `pre-install`, `post-install` | after rendering, before any of the release's other objects is created; after all of them are created |
| `pre-upgrade`, `post-upgrade` | after rendering, before any of the release's other objects is updated; after all of them are updated |
| `pre-rollback`, `post-rollback` | before any of the release's other objects is rolled back; after all of them are modified |
| `pre-delete`, `post-delete` | before any of the release's other objects is deleted; after all of them are deleted |
| `test` | when `helm test` runs |

One object can list several events, as in `"helm.sh/hook": pre-upgrade,pre-delete,pre-rollback`; Helm trims and lowercases each value, so `" Pre-Upgrade , POST-install "` works too.
*"When subcharts declare hooks, those are also evaluated. There is no way for a top-level chart to disable the hooks declared by subcharts."*

**A misspelled event drops the whole object:** with `"helm.sh/hook": pre-upgarde`, `helm template` logged `level=INFO msg="skipping unknown hooks" hookTypes=pre-upgarde` and rendered the object neither as a hook nor as a regular object.

**Post hooks don't wait for the objects to be ready:** they run as soon as Helm has created or updated the objects.
`--wait`, a flag of `helm install`, `helm upgrade`, and `helm rollback`, changes that; the documentation describes it for an install: *"the library will wait until all resources are in a ready state and will not run the `post-install` hook until they are ready."*:

```bash
helm -n helm-hooks upgrade demo-hooks helm-hooks --wait
```

In Helm's source, all three commands wait for the release's objects between applying them and running the post hooks.
Without the flag, Helm 4 uses the `hookOnly` strategy, which waits only for hooks; `--wait` alone selects the `watcher` strategy, and `--rollback-on-failure` selects it too.

## The annotations

| Annotation | Purpose | Values | Default |
|---|---|---|---|
| `helm.sh/hook` | marks the object as a hook, and names the events Helm runs it on | one or more events | required |
| `helm.sh/hook-weight` | orders the hooks of one event: Helm runs the lowest weight first, and waits for it before the next | an integer, written as a string, such as `"-5"` | `"0"` |
| `helm.sh/hook-delete-policy` | decides when Helm deletes the hook's objects: before the hook's next run, after it succeeds, or after it fails | `before-hook-creation`, `hook-succeeded`, `hook-failed` | `before-hook-creation`, only when the annotation is absent |
| `helm.sh/hook-output-log-policy` | prints the logs of a Job or Pod hook in Helm's output, after it succeeds or fails | `hook-succeeded`, `hook-failed` | no output |

**A weight has to be an integer in a string:** *"Hook weights can be positive or negative numbers but must be represented as strings."*
A value that isn't an integer, such as `"five"`, silently becomes 0.

An unquoted `-5` is read as -5 by Helm, but rejected by Kubernetes, whose annotation values are strings: a server-side dry run of the object failed with `cannot unmarshal number into Go struct field ObjectMeta.metadata.annotations of type string`.

**Naming any deletion policy replaces the default:** Helm's source adds `before-hook-creation` only to a hook without the annotation.
A misspelled value such as `hook-succeded` is kept as the hook's only policy, so Helm never deletes the hook's objects.

**`helm.sh/hook-output-log-policy` prints a hook's logs:** Helm 3.18 added it, and the hooks documentation doesn't list it yet; Helm's source reads it for Job and Pod hooks only.

With `hook-succeeded` on `backup-db`, an upgrade printed its output before Helm's own, `level=INFO msg="Backing up some data."`.
With `hook-failed` on a failing `backup-db`, a failed upgrade printed its output once for each of the Job's three failed Pods.

`helm template` renders hooks with the other objects.
`--no-hooks` leaves out every hook, the scaffold's `test` Pod included, while `helm template --skip-tests` leaves out only the tests.

## How Helm runs a hook

Helm waits for a hook before it continues: *"If the resource is a `Job` or `Pod` kind, Helm will wait until it successfully runs to completion. And if the hook fails, the release will fail."*
Other kinds count as ready once they're created.

With `backup-db` as a `pre-upgrade` hook, an upgrade that changed nginx's image tag took 8.4 seconds, against 0.4 for the install: the Job ran for 7 seconds, most of it pulling `alpine`, and nginx's new Pod was created only after it completed.

**Each hook gets `--timeout` to finish:** the flag's help describes it as the *"time to wait for any individual Kubernetes operation (like Jobs for hooks)"*, five minutes by default.

**Weights order the hooks of one event:** the lower weight runs first, and the next hook starts only after it.
With both hooks on `pre-upgrade`, and `backup-db` sleeping 10 seconds, `backup-db` ran from 10:10:07 to 10:10:20, and Helm created `second` at 10:10:20.

**Equal weights run in name order:** the documentation says *"The library sorts hooks by weight (assigning a weight of 0 by default), by resource kind and finally by name in ascending order."*
In a separate test chart, two `pre-install` hooks with weight `"0"`, a Job `aa-order-job` and a ConfigMap `zz-order-cm`, ran Job first: Helm's source breaks ties by the object's `metadata.name` only.

Both hooks were in one file, so file names play no part, and renaming files changes nothing.
Hooks whose order matters need different weights.

**`helm uninstall` runs the hooks stored in the release:** a `sleep 15` removed from `backup-db`, a `pre-delete` hook, in the chart's directory still ran during `helm uninstall`.
A change takes effect once an upgrade stores it in the release.

## Deletion policies

| Policy | The hook's Job and Pods |
|---|---|
| `before-hook-creation` | stay after the run, and are deleted just before the same hook runs again |
| `hook-succeeded` | are deleted once the hook succeeds |
| `hook-failed` | are deleted if the hook fails |

**Each policy acts on its own hook:** `before-hook-creation` deletes only the previous object with the same name.
After an upgrade that ran only `backup-db`, the `second` Job from an earlier run was still there.

**`hook-succeeded` alone skips a hook in Helm 4:** if a completed Job from an earlier run still exists, Helm 4 applies the hook with server-side apply, which updates that Job in place instead of creating a new one.
Helm then finds it complete, counts the hook as succeeded, and deletes it: an upgrade with `hook-succeeded` as `backup-db`'s only policy succeeded, and the Job's events showed no new Pod.

With `--server-side=false`, the same upgrade failed with `jobs.batch "demo-hooks-helm-hooks-backup-db" already exists`, as it did in Helm 3.
A hook whose name doesn't change between runs needs `before-hook-creation` in its policy, written out once any other policy is set.

## Failures

**A failed pre-hook stops the operation before any change:** with `backup-db` as a `pre-upgrade` hook that exits with code 1, an upgrade failed with `pre-upgrade hooks failed: … Job Failed. failed: 3/1` once the Job's three attempts had failed.
The revision was recorded as `failed`, and nginx kept its Pod and image, although the upgrade changed its image tag.

**A failed post-hook leaves the changes in place:** with the failing `backup-db` as a `post-upgrade` hook, an upgrade that changed nginx's image tag replaced nginx's Pod while the hook was still failing, and the new Pod stayed afterwards.
Helm doesn't revert the objects it has already updated.

**`--rollback-on-failure` rolls back to the last successful revision:** `helm upgrade --help` describes the flag, *"if set, Helm will rollback the upgrade to previous success release upon failure."*
The release's history showed where it went back to:

| Revision | What happened |
|---|---|
| 4 | a successful upgrade |
| 5 | the failed `post-upgrade` run above |
| 6 | the same failure, with `--rollback-on-failure` |
| 7 | `Rollback to 4`, added by the flag |

Helm went back to revision 4, the last successful one, not to revision 5, and the rollback ran `second`, whose events include `pre-rollback`.
The flag replaces Helm 3's `--atomic`, which now prints `Flag --atomic has been deprecated, use --rollback-on-failure instead`.

## Hooks aren't part of the release

*"The resources that a hook creates are currently not tracked or managed as part of the release."*
After `helm uninstall demo-hooks`, the Jobs of `backup-db` and `second` remained with their Pods, and had to be deleted by hand.

The documentation names the alternatives: *"either add a custom `helm.sh/hook-delete-policy` annotation to the hook template file, or set the time to live (TTL) field of a Job resource"*.
A hook object that must outlive everything carries `helm.sh/resource-policy: keep` instead.

**A hook's Pod can receive Service traffic:** `backup-db`'s Pod template copies the Deployment's labels, the Service's selector labels among them, so the chart's Service selects its Pod too.
While `backup-db` slept for 15 seconds, the Service's EndpointSlice listed its Pod as a ready endpoint next to nginx's.
A hook needs labels that the Service doesn't select.

## Verify

From `06-advanced-topics/05-hook-weights`, the chart has the scaffold's `test` hook, from `templates/tests/test-connection.yaml`, and two hooks of its own with different events and weights:

```bash
helm template demo-hooks helm-hooks | grep -E '^# Source: .*/hooks/|"helm.sh/hook'
```

```text
    "helm.sh/hook": test
# Source: helm-hooks/templates/hooks/backup-db.yaml
    "helm.sh/hook": pre-upgrade,pre-delete,pre-rollback
    "helm.sh/hook-weight": "0"
    "helm.sh/hook-delete-policy": before-hook-creation
# Source: helm-hooks/templates/hooks/second-hook.yaml
    "helm.sh/hook": pre-delete,pre-rollback
    "helm.sh/hook-weight": "1"
    "helm.sh/hook-delete-policy": before-hook-creation
```
