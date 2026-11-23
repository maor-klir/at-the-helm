#helm #kubernetes #dependencies

# Chart dependencies

A chart can include other charts as its dependencies, also called subcharts, and Helm installs them together with it as one release.
The Charts documentation describes both ways: *"In Helm, one chart may depend on any number of other charts. These dependencies can be dynamically linked using the `dependencies` field in `Chart.yaml` or brought in to the `charts/` directory and managed manually."*

A dependency is either required for the chart to work, or enables an optional feature that a value or tag can turn on.

## Common uses

| Use | Example |
|---|---|
| A database the application needs | the `config-store` chart in `05-chart-dependencies-subcharts/` depends on Bitnami's `postgresql` chart |
| A service several applications share | a cache or a message broker, packaged once as a chart |
| Shared template code | Bitnami's `postgresql` chart itself depends on the `common` library chart |

A library chart deploys nothing: *"A library chart is a type of Helm chart that defines chart primitives or definitions which can be shared by Helm templates in other charts."*

## Declaring a dependency

`config-store`'s `Chart.yaml` declares one dependency:

```yaml
dependencies:
  - name: postgresql
    version: '16.2.2'
    repository: 'https://charts.bitnami.com/bitnami'
```

The `helm dependency` reference describes the three fields:

- **`name`:** *"The 'name' should be the name of a chart, where that name must match the name in that chart's 'Chart.yaml' file."*
- **`version`:** *"The 'version' field should contain a semantic version or version range."*
- **`repository`:** *"The 'repository' URL should point to a Chart Repository. Helm expects that by appending '/index.yaml' to the URL, it should be able to retrieve the chart repository's index."*

**An `https://` repository has to be added first:** the Charts documentation adds, *"Note that you must also use `helm repo add` to add that repo locally."*
Without it, Helm 4 stops with `Error: no repository definition for https://charts.bitnami.com/bitnami. Please add the missing repos via 'helm repo add'`.

`repository` also accepts a repository's name, as `@bitnami` or `alias:bitnami`, an `oci://` registry, or a local path starting with `file://`.
A local path needs no `helm repo add`: *"If the dependency chart is retrieved locally, it is not required to have the repository added to helm by "helm add repo"."*
An `oci://` registry needs none either, since Helm pulls from it directly (see **53 - OCI registries and classic chart repositories**).

Other optional fields, `condition`, `tags`, `alias`, and `import-values`, control whether a dependency is installed, under which name, and which of its values the parent reads (see **55 - Enabling subcharts with conditions and tags** and **54 - Passing values to subcharts**).
An `alias` also becomes the dependency's key in the parent's values.
The best practices ask for them on optional dependencies: *"Conditions or tags should be added to any dependencies that _are optional_."*

## The `charts/` directory

`helm dependency update` and `build` store each dependency as an archive, such as `charts/postgresql-16.2.2.tgz`.
A dependency can also be an unpacked chart directory in `charts/`; the chart loader ignores names that start with `_` or `.`.

**A dependency without a repository must already be in `charts/`:** *"Helm cannot perform dependency management operations on the dependency when the `repository` field is left blank. In that case Helm will assume the dependency is in a sub-directory of the `charts` folder with the name being the same as the `name` property for the dependency."*

With `charts/postgresql/` unpacked, `helm dependency update` reports `Dependency postgresql did not declare a repository. Assuming it exists in the charts directory`, and writes `repository: ""` to `Chart.lock`.
Without the directory, the update fails with `Error: directory config-store/charts/postgresql not found`, and rendering fails with `found in Chart.yaml, but missing in charts/ directory: postgresql`.

**The local chart must still match `version`:** with `version: '16.2.0'` and 16.2.2 unpacked, the update fails with `Error: dependency postgresql at version 16.2.2 does not satisfy the constraint 16.2.0`.

## The three commands

| Command | What it does | Tested on `config-store` |
|---|---|---|
| `helm dependency list <chart>` | *"List all of the dependencies declared in a chart."* | `STATUS` is `ok`, `missing` without the archive, or `unpacked` for a directory |
| `helm dependency update <chart>` | *"Update the on-disk dependencies to mirror Chart.yaml."*, resolving version ranges and writing `Chart.lock` | `version: '~16.2.0'` resolved to `16.2.5` |
| `helm dependency build <chart>` | *"Build out the charts/ directory from the Chart.lock file."* | downloaded `16.2.2`, byte-identical to the committed archive |

`update` chooses versions; `build` repeats the choice recorded in `Chart.lock`, which is why a chart's archive can be rebuilt from its lock file on any machine.

**`install`, `upgrade`, and `template` can fetch a missing dependency:** without the archive, `helm template` fails with `You may need to run 'helm dependency build' to fetch missing dependencies: found in Chart.yaml, but missing in charts/ directory: postgresql`.
With `--dependency-update`, it downloaded 16.2.2 and rendered.
Helm's source shows that the flag runs `update`, not `build`, and only when a dependency is missing, so with a version range it can choose a newer version and rewrite `Chart.lock`.

## `Chart.lock`

`update` records the exact versions it chose: *"On successful update, this will generate a lock file that can be used to rebuild the dependencies to an exact version."*

```yaml
dependencies:
- name: postgresql
  repository: https://charts.bitnami.com/bitnami
  version: 16.2.2
digest: sha256:fc33a0754bffd04a07fd4de4805d5b89eebd7d5124aae907095695061539d0d7
generated: "2024-11-22T19:11:46.399297+01:00"
```

**`build` refuses a lock that no longer matches:** with `Chart.yaml` changed to `16.2.1`, it fails with `Error: the lock file (Chart.lock) is out of sync with the dependencies file (Chart.yaml). Please update the dependencies with 'helm dependency update'`.
Without any lock file, *"'helm dependency build' will mirror the behavior of 'helm dependency update'."*

**The `digest` covers the declarations, not the archives:** Helm's source computes it as a SHA-256 of the `dependencies` in `Chart.yaml` together with the locked list.
Any change to a dependency entry puts the lock out of sync: adding only `condition: postgresql.enabled` gives the same error.
The same declarations locked to the same versions give the same `digest` on any machine.

The best practices suggest patch-level ranges such as `~16.2.2` over exact versions; a range and a lock file together allow updates on purpose and repeatable builds the rest of the time (see **02 - Benefits and limitations of Helm**).

**A minor version can change a default:** Bitnami's `postgresql` chart 16.6.0 set `auth.usePasswordFiles` to `true`, so PostgreSQL reads its passwords from mounted files instead of environment variables.
With `version: '^16.2.2'`, `helm dependency update` resolved to 16.7.27 and brought that change in; `~16.2.2` resolved to 16.2.5.

## Where the archive comes from

Bitnami's repository index points into an OCI registry: building from `https://charts.bitnami.com/bitnami` prints `Pulled: registry-1.docker.io/bitnamicharts/postgresql:16.2.2`.
The `repository` in `Chart.yaml` names where Helm looks the chart up, and the index entry decides where the archive is downloaded from.

How a parent passes values to its dependencies is in **54 - Passing values to subcharts**, and the `--set` paths for them in **13 - Overriding chart values**.

## Verify

From `05-chart-dependencies-subcharts/02-add-postgres-dependency/subcharts/config-store`, our chart declares the `postgresql` dependency, holds its archive, and renders its templates:

```bash
helm dependency list .
helm template . | grep -c '^# Source: config-store/charts/postgresql/'
```

```text
NAME      	VERSION	REPOSITORY                        	STATUS
postgresql	16.2.2 	https://charts.bitnami.com/bitnami	ok

7
```
