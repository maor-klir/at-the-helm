#helm #kubernetes

# Uninstalling releases and persistent data

`helm uninstall` deletes the objects Helm installed, not everything the release created or relies on.
Objects that Helm never managed, and the data on volumes, can outlive the release.
A reinstall on top of that data fails when the chart generates new credentials.

## What `helm uninstall` deletes

The reference page sums it up: *"It removes all of the resources associated with the last release of the chart as well as the release history, freeing it up for future use."*

The resources are the objects in the release manifest, the ones `helm get manifest` prints (see **11 - Exploring charts and releases with the Helm CLI**).
The release history is the release record, the `sh.helm.release.v1.<release>.v<revision>` Secrets (see **01 - The role of Helm in Kubernetes**).

For our WordPress release, the manifest holds a Deployment, a StatefulSet, two Services, two Secrets, a ConfigMap, two NetworkPolicies, two PodDisruptionBudgets, two ServiceAccounts, and one PersistentVolumeClaim, `local-wp-wordpress`.
`helm -n wordpress uninstall local-wp` deleted all of them, together with the release record.

**`--keep-history` keeps the record:** the flag is described as *"remove all associated resources and mark the release as deleted, but retain the release history"*.

`helm list --uninstalled` then shows the release, an option the reference page limits to that case: *"show uninstalled releases (if 'helm uninstall --keep-history' was used)"*.
Plain `helm list` shows it too, with the status `uninstalled`, because it lists releases in any status (see **11 - Exploring charts and releases with the Helm CLI**).

Without the flag, the Using Helm guide notes, *"it is no longer possible to rollback an uninstalled resource."*

**Other flags shape the deletion itself:** `--dry-run` lists what would be uninstalled without deleting anything.
`--cascade` selects how dependents are deleted and defaults to `background`.
The reference page pairs it with waiting: *"Use '--cascade foreground' with '--wait' to ensure resources with finalizers are fully deleted before the command returns."*

## What it leaves behind

| Object | Created by | After `helm uninstall` |
|---|---|---|
| Deployment, StatefulSet, Services, Secrets, ConfigMap, and the rest of the manifest | the chart's templates | deleted |
| PVC `local-wp-wordpress` and its PersistentVolume | the chart's templates | deleted |
| PVC `data-local-wp-mariadb-0` and its PersistentVolume | the StatefulSet controller | kept, still `Bound` |
| release record Secrets | Helm | deleted, unless `--keep-history` |
| namespace `wordpress` | `helm install --create-namespace` | kept |
| objects created with `kubectl` | us | kept |

**Whether a PVC survives depends on what created it:** a PVC in the chart's templates is deleted with the release unless it carries `helm.sh/resource-policy: keep`, and a PVC that a StatefulSet created from its `volumeClaimTemplates` is never deleted by Helm.

### Objects Helm never managed

**StatefulSet PVCs come from the controller, not the chart:** a StatefulSet lists `volumeClaimTemplates`, and the Kubernetes StatefulSet documentation says *"For each VolumeClaimTemplate entry defined in a StatefulSet, each Pod receives one PersistentVolumeClaim."*

The MariaDB StatefulSet's template is named `data`, so its only Pod gets `data-local-wp-mariadb-0`.
That PVC is not in the release manifest, so `helm uninstall` doesn't touch it.

**Kubernetes keeps those PVCs on purpose:** the same documentation says *"Deleting and/or scaling a StatefulSet down will _not_ delete the volumes associated with the StatefulSet. This is done to ensure data safety, which is generally more valuable than an automatic purge of all related StatefulSet resources."*

The behavior is set by `.spec.persistentVolumeClaimRetentionPolicy`, with `whenDeleted` and `whenScaled`, and *"The default for policies is `Retain`"*.
Our MariaDB StatefulSet has `{"whenDeleted":"Retain","whenScaled":"Retain"}`, and chart 23.1.20's values offer no setting to change it.

**The namespace and hand-made objects stay too:** in Helm's source, `--create-namespace` creates the namespace separately from the release manifest, so uninstalling the release leaves the namespace.
Objects we created ourselves with `kubectl`, such as a Service from `kubectl expose`, were never part of the release either.

### Objects a chart marks to keep

A chart can exclude one of its own objects from deletion.
Helm's chart tips page says *"The annotation `helm.sh/resource-policy: keep` instructs Helm to skip deleting this resource when a helm operation (such as `helm uninstall`, `helm upgrade` or `helm rollback`) would result in its deletion."*
The cost is that *"this resource becomes orphaned. Helm will no longer manage it in any way."*

The WordPress chart doesn't set the annotation on `local-wp-wordpress`, so Helm deleted that PVC with the release.

## PersistentVolumes and the reclaim policy

Deleting a PVC doesn't decide the PersistentVolume's fate; the PV's reclaim policy does.
The Kubernetes PersistentVolume documentation describes both values:

> *"For volume plugins that support the `Delete` reclaim policy, deletion removes both the PersistentVolume object from Kubernetes, as well as the associated storage asset in the external infrastructure."*
>
> *"When the PersistentVolumeClaim is deleted, the PersistentVolume still exists and the volume is considered "released"."*

The second describes `Retain`, where the old data stays on the volume until someone deletes it.
Dynamically provisioned volumes *"inherit the reclaim policy of their StorageClass, which defaults to `Delete`"*.

**On our cluster the policy is `Delete`:** k3s's default StorageClass is `local-path` (provisioner `rancher.io/local-path`, `WaitForFirstConsumer`).
Each time we deleted a leftover MariaDB PVC, its PV disappeared with it.
`kubectl get pv` shows the policy per volume in its `RECLAIM POLICY` column.

## Generated values and a reused volume

The WordPress chart generates random passwords for any it isn't given.
They land in two Secrets: `local-wp-mariadb` holds `mariadb-password`, for the `bn_wordpress` user, and `mariadb-root-password`, and `local-wp-wordpress` holds `wordpress-password`.
MariaDB writes the users and their passwords into its data directory on the first start, on the PVC.

**An uninstall splits the two:** the Secrets go with the release, while the data on `data-local-wp-mariadb-0` stays.
A reinstall under the same release name produces the same StatefulSet and PVC names, so the new MariaDB Pod mounts the old volume.
The chart, meanwhile, generates new passwords, and both came out different from the first install.

**Neither side accepts the other's passwords:** we reinstalled on the old volume and watched the Pods for three minutes.

- WordPress logs `Trying to connect to the database server`, then after a minute `Could not connect to the database`, and ends up in `CrashLoopBackOff` without ever becoming ready.
- MariaDB logs `Access denied for user 'bn_wordpress'`, from WordPress, and `Access denied for user 'root'@'localhost'`, from its own liveness probe, which runs `mariadb-admin status` with the new root password.
- The events show `Container mariadb failed liveness probe, will be restarted`. Its readiness probe, `mariadb-admin ping`, passes on and off, so the Pod switches between ready and not ready.

The WordPress chart's README states the rule behind it:

> *"Once this chart is deployed, it is not possible to change the application's access credentials, such as usernames or passwords, using Helm. To change these application credentials after deployment, delete any persistent volumes (PVs) used by the chart and re-deploy it, or use the application's built-in administrative tools if available."*

**There are two ways out:** delete the PVC, and with `Retain` also the PV, so the reinstall starts from empty data.
Or keep the data and pass the old passwords back at install time, the approach the README's upgrade instructions take with `mariadb.auth.rootPassword` and `mariadb.auth.password`.
Setting the passwords ourselves from the first install avoids the problem altogether.

## Cleaning up completely

After the uninstall, the leftovers are the StatefulSet's PVC and the namespace:

```bash
helm -n wordpress uninstall local-wp
kubectl -n wordpress get pvc                              # data-local-wp-mariadb-0
kubectl -n wordpress delete pvc data-local-wp-mariadb-0   # its PV goes too, reclaim Delete
kubectl get pv                                            # No resources found
kubectl delete namespace wordpress
```

Deleting the namespace alone would also delete the PVC, since PVCs are namespaced objects.

## Verify

With the release installed, the manifest holds only the WordPress PVC, and the MariaDB StatefulSet carries its own claim template and retention policy:

```bash
helm -n wordpress get manifest local-wp | grep -A3 '^kind: PersistentVolumeClaim' | grep 'name:'
kubectl -n wordpress get sts local-wp-mariadb \
  -o jsonpath='{.spec.volumeClaimTemplates[*].metadata.name}{"\n"}{.spec.persistentVolumeClaimRetentionPolicy}{"\n"}'
kubectl get sc local-path -o jsonpath='{.reclaimPolicy}{"\n"}'   # Delete
```

After `helm -n wordpress uninstall local-wp`, only the MariaDB PVC and the namespace remain:

```bash
kubectl -n wordpress get pvc      # data-local-wp-mariadb-0
kubectl -n wordpress get secret   # No resources found
kubectl get ns wordpress          # Active
kubectl get pv -o custom-columns=NAME:.metadata.name,CLAIM:.spec.claimRef.name,RECLAIM:.spec.persistentVolumeReclaimPolicy,STATUS:.status.phase
```
