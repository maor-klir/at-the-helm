#helm #kubernetes

# Upgrading releases

`helm upgrade` changes an installed release in place, to new values, a new chart version, or both.
Every upgrade writes a new revision, and the previous ones stay in the release's history.
Which values the new revision gets depends on the flags we pass.

## What an upgrade does

The Using Helm guide: *"An upgrade takes an existing release and upgrades it according to the information you provide. Because Kubernetes charts can be large and complex, Helm tries to perform the least invasive upgrade. It will only update things that have changed since the last release."*

The command takes the release and the chart: *"The upgrade arguments must be a release and chart."*
A chart reference without a version moves to the newest one: *"For chart references, the latest version will be specified unless the '--version' flag is set."*
Our WordPress release would jump from 23.1.20 to 34.x, so every upgrade pins `--version`.

Helm 4 applies an upgrade the same way it applied the install, server-side apply for our release (see **02 - Benefits and limitations of Helm**).

**Under server-side apply, Helm sends every object:** the debug output of an upgrade logs `checking resources for changes resources=14`, then `Patched resource` for each of the 14 objects, changed or not.
The API server works out which fields actually change.

## Values on upgrade

| Flags | Chart defaults | Earlier user-supplied values | New `-f` and `--set` |
|---|---|---|---|
| none, and no `-f` or `--set` | new chart | reused | — |
| only `-f` or `--set` | new chart | dropped | applied |
| `--reuse-values` | the old release's merged values | reused | merged on top |
| `--reset-values` | new chart | dropped | applied |
| `--reset-then-reuse-values` | new chart | reused | merged on top |

The first two rows come from Helm's source: the release's values are reused only when the upgrade passes no values at all.
The `helm upgrade` reference describes the three flags:

| Flag | Reference description |
|---|---|
| `--reuse-values` | *"when upgrading, reuse the last release's values and merge in any overrides from the command line via --set and -f. If '--reset-values' is specified, this is ignored"* |
| `--reset-values` | *"when upgrading, reset the values to the ones built into the chart"* |
| `--reset-then-reuse-values` | *"when upgrading, reset the values to the ones built into the chart, apply the last release's values and merge in any overrides from the command line via --set and -f."* |

**`--reuse-values` also keeps the old chart's defaults:** in Helm's source, the flag replaces the new chart's default values with the old release's merged values (`chart.Values = oldVals`).
For an upgrade on the same chart version, that changes nothing.
For a chart upgrade, the new chart's defaults never apply.

A server-side dry run of our upgrade from 23.1.20 to 23.1.28 shows the effect on the images:

| Upgrade with | WordPress image | MariaDB image |
|---|---|---|
| `--reuse-values` | `6.6.2-debian-12-r7` | `11.4.3-debian-12-r1` |
| `--reset-then-reuse-values`, or no values flags | `6.6.2-debian-12-r18` | `11.4.4-debian-12-r0` |

**Merged keys stay until something resets them:** our upgrade to autoscaling passed a file without `replicaCount`, together with `--reuse-values`.
`replicaCount: 3` from the install stayed in the release's values, merged with the new `autoscaling` block.
`--reset-then-reuse-values` would keep it as well; only `--reset-values`, or a file passed without a reuse flag, drops it.

## Generated values across upgrades

The WordPress chart generated the MariaDB passwords at install, and they came through the upgrade unchanged.
That is the chart's work, not Helm's: its `common.secrets.passwords.manage` helper reads the existing Secret with `lookup` and returns the stored password.
`--reuse-values` only carries over values that were supplied.

`lookup` needs the cluster.
Helm's template guide says *"Helm is not supposed to contact the Kubernetes API Server during a `helm template|install|upgrade --dry-run` operation."*
It adds that *"`helm template|install|upgrade --dry-run=server` should be used instead to allow cluster connection."*

## Revisions and history

Each upgrade adds one revision and one release record Secret, `sh.helm.release.v1.local-wp.v2` after the first upgrade (see **01 - The role of Helm in Kubernetes**).
`helm history` lists them, the latest `deployed` and the earlier ones `superseded`.
Its reference: *"A default maximum of 256 revisions will be returned."*

`helm get values local-wp --revision 1` prints the values of an earlier revision, which shows what an upgrade changed.

**`--history-max` limits how many revisions Helm keeps:** the reference describes it as *"limit the maximum number of revisions saved per release. Use 0 for no limit (default 10)"*.
In Helm's source, storing a new revision first deletes the oldest records until the history fits the limit.

## Chart versions

Helm's chart documentation: *"Every chart must have a version number. A version should follow the SemVer 2 standard but it is not strictly enforced."*
The Semantic Versioning specification sets what each number means:

> *"MAJOR version when you make incompatible API changes"*
>
> *"MINOR version when you add functionality in a backward compatible manner"*
>
> *"PATCH version when you make backward compatible bug fixes"*

Going from 23.1.20 to 23.1.28 is a patch upgrade: the chart changed, and the app version stayed WordPress 6.6.2 (see **11 - Exploring charts and releases with the Helm CLI**).

## Fields an upgrade stops rendering

Turning on autoscaling made the chart stop rendering `spec.replicas` in the WordPress Deployment.
The Kubernetes server-side apply documentation says what happens to a field that disappears from the applied manifest:

> *"If you remove a field from a manifest and apply that manifest, Server-Side Apply checks if there are any other field managers that also own the field. If the field is not owned by any other field managers, it is either deleted from the live object or reset to its default value, if it has one."*

Helm was the only manager of `replicas`, so the field fell back to its default of 1, and two of the three Pods were deleted.
Fifteen seconds later, the HorizontalPodAutoscaler raised the Deployment to its minimum of 2.

## Verify

After the upgrade to autoscaling (revision 2), the history, the merged values, and the release records:

```bash
helm -n wordpress history local-wp                    # 1 superseded, 2 deployed
helm -n wordpress get values local-wp                 # replicaCount: 3 next to autoscaling
helm -n wordpress get values local-wp --revision 1    # no autoscaling
kubectl -n wordpress get secret | grep sh.helm.release   # .v1 and .v2
```

The scaling events of that upgrade, and the autoscaler afterwards:

```bash
kubectl -n wordpress get events --sort-by=.lastTimestamp | grep -E 'Scaled|New size'
# Scaled down replica set local-wp-wordpress-… from 3 to 1
# New size: 2; reason: Current number of replicas below Spec.MinReplicas
kubectl -n wordpress get hpa local-wp-wordpress   # min 2, max 10, replicas 2
```

The image each values flag renders for the chart upgrade, without changing the release:

```bash
helm -n wordpress upgrade local-wp bitnami/wordpress --version 23.1.28 --reuse-values --dry-run=server | grep 'image:'
helm -n wordpress upgrade local-wp bitnami/wordpress --version 23.1.28 --reset-then-reuse-values --dry-run=server | grep 'image:'
```
