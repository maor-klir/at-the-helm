# Adding PostgreSQL as a chart dependency

## Overview

In this exercise, we'll add Bitnami's PostgreSQL chart to config-store as a dependency, download it, and compare `helm dependency update`, `build`, and `list`.
Here's a quick summary of the main steps:

1. Find the PostgreSQL chart in the Bitnami repository.
2. Declare it under `dependencies` in `Chart.yaml`.
3. Download it with `helm dependency update`, and rebuild it from `Chart.lock` with `helm dependency build`.
4. Point its image to `bitnamilegacy`, and render the chart.

## Step-by-step guide

The chart in `subcharts/config-store/` is the end state of this exercise, and continues from exercise 01's chart.
To build it yourself, copy exercise 01's `subcharts` directory into an empty directory, and run the steps there.

1. **Check the repository:**

   ```bash
   helm repo list
   helm repo update
   ```

   `helm repo list` shows `bitnami` with the URL `https://charts.bitnami.com/bitnami`, added in the fundamentals section.
   `helm repo update` downloads each repository's current index to the local cache, which `helm search repo` reads.

2. **Search for the chart:**

   ```bash
   helm search repo postgresql
   ```

   The first row is `bitnami/postgresql`, now at chart version 18.12.23 with app version 18.7.0. This chart uses 16.2.2, the version the search found when the course was recorded:

   ```bash
   helm search repo bitnami/postgresql --version 16.2.2
   ```

   ```text
   NAME                 	CHART VERSION	APP VERSION	DESCRIPTION
   bitnami/postgresql   	16.2.2       	17.2.0     	PostgreSQL (Postgres) is an open source object-...
   bitnami/postgresql-ha	16.2.2       	17.6.0     	This PostgreSQL cluster solution includes the P...
   ```

   `bitnami/postgresql-ha` appears as well, since its name contains the search term.

   **Why 16.2.2, not the latest:** later versions change what the chart renders.

   | Version | Change |
   |---|---|
   | 16.6.0 and later | `auth.usePasswordFiles` defaults to `true`, so PostgreSQL reads its passwords from files mounted from the Secret, not from environment variables |
   | 16.6.0 | rejects the `bitnamilegacy` image from step 8 with *"Original containers have been substituted for unrecognized ones"* unless `global.security.allowInsecureImages=true`; 16.7.27, the last 16.x, accepts it with a warning |
   | 18.x | renders `bitnami/postgresql:latest`, a rolling tag |

   The course's announcement on `usePasswordFiles` names 16.6.6; Bitnami's changelog lists the change under 16.6.0.

3. **Declare the dependency:**

   At the end of `Chart.yaml`:

   ```yaml
   dependencies:
     - name: postgresql
       version: '16.2.2'
       repository: 'https://charts.bitnami.com/bitnami'
   ```

   | Field | Value |
   |---|---|
   | `name` | the chart's own name, `postgresql`; the `bitnami/` prefix in the search results is the name we gave the repository with `helm repo add` |
   | `version` | the chart version, not the app version |
   | `repository` | the repository's URL, as `helm repo list` shows it; Helm 4 also needs the repository added with `helm repo add` |

   The Charts documentation lists the other fields of a dependency; exercise 06 uses `condition` and `tags` (see **51 - Chart dependencies**).

4. **Download the dependency:**

   `helm dependency update` works on a chart directory, the current one by default. From `subcharts/`, it fails with `Error: Chart.yaml file is missing`. From the chart's directory:

   ```bash
   cd config-store
   helm dependency update
   ```

   ```text
   Hang tight while we grab the latest from your chart repositories...
   ...Successfully got an update from the "maor-klir" chart repository
   ...Successfully got an update from the "kyverno" chart repository
   ...Successfully got an update from the "argo" chart repository
   ...Successfully got an update from the "bitnami" chart repository
   ...Successfully got an update from the "prometheus-community" chart repository
   Update Complete. ⎈Happy Helming!⎈
   Saving 1 charts
   Downloading postgresql from repo https://charts.bitnami.com/bitnami
   Pulled: registry-1.docker.io/bitnamicharts/postgresql:16.2.2
   Digest: sha256:c606abf37a17ffd8a7db17accd07b3287f80f9eafab5539c1215cb4e148a2e57
   Deleting outdated charts
   ```

   The command refreshes every repository first, as `helm repo update` does; `--skip-refresh` skips that. Bitnami's index sends the 16.2.2 download to its OCI registry, `registry-1.docker.io/bitnamicharts`.

   It writes the archive to `charts/postgresql-16.2.2.tgz`, and the chosen version to `Chart.lock`:

   ```yaml
   dependencies:
   - name: postgresql
     repository: https://charts.bitnami.com/bitnami
     version: 16.2.2
   digest: sha256:fc33a0754bffd04a07fd4de4805d5b89eebd7d5124aae907095695061539d0d7
   generated: "2024-11-22T13:31:41.668964+01:00"
   ```

   Our run downloaded an archive byte-identical to the course's and wrote the same `digest`, which Helm computes from the dependencies in `Chart.yaml` and the locked versions, not from the archive.
   Only `generated`, the time of the update, differs. The copy here keeps the course's `Chart.lock`.

5. **Rebuild from the lock file:**

   ```bash
   rm charts/postgresql-16.2.2.tgz
   helm dependency list
   helm dependency build
   ```

   `list` shows the dependency as `missing`. `build` downloads 16.2.2 again, with the same output as `update`, and leaves `Chart.lock` unchanged.

6. **Change the version:**

   In `Chart.yaml`, set the dependency's `version` to `'16.2.0'`, and build again:

   ```bash
   helm dependency build
   ```

   ```text
   Error: the lock file (Chart.lock) is out of sync with the dependencies file (Chart.yaml). Please update the dependencies with 'helm dependency update'
   ```

   `helm dependency list` now shows `wrong version`. `helm dependency update` writes 16.2.0 to `Chart.lock`, downloads `postgresql-16.2.0.tgz`, and deletes the 16.2.2 archive: that's its last line, `Deleting outdated charts`.
   16.2.0 downloads from `charts.bitnami.com` itself, with no `Pulled:` line, because the index gives each version its own URL.

   | Command | Reads | Writes `Chart.lock` |
   |---|---|---|
   | `helm dependency update` | `Chart.yaml` | yes |
   | `helm dependency build` | `Chart.lock` | no, and fails when it's out of sync with `Chart.yaml` |

   Set the version back to `'16.2.2'`, and run `helm dependency update` once more.

7. **List the dependencies:**

   ```bash
   helm dependency list
   ```

   ```text
   NAME      	VERSION	REPOSITORY                        	STATUS
   postgresql	16.2.2 	https://charts.bitnami.com/bitnami	ok
   ```

8. **Point the image to `bitnamilegacy`:**

   At the end of `values.yaml`:

   ```yaml
   postgresql:
     image:
       repository: bitnamilegacy/postgresql
   ```

   Chart 16.2.2 renders `docker.io/bitnami/postgresql:17.2.0-debian-12-r0`, a tag Bitnami removed from `bitnami/`. It remains in `bitnamilegacy/`, which no longer gets updates.
   The key `postgresql` passes values to the dependency of that name, which exercise 03 covers.

   ```bash
   helm template . | grep bitnamilegacy/postgresql
   ```

   ```text
             image: docker.io/bitnamilegacy/postgresql:17.2.0-debian-12-r0
   ```

   The course's announcement also sets `registry: docker.io`, the chart's default, so it's left out here.

9. **Render the chart:**

   ```bash
   helm lint .
   helm template . | grep -E '^(# Source|kind)'
   ```

   The lint passes. The chart now renders 11 objects instead of 4, and 7 of them come from `config-store/charts/postgresql/templates/`: a NetworkPolicy, a PodDisruptionBudget, a ServiceAccount, a Secret, two Services, and the StatefulSet that runs the database.

   The dependency is a complete chart, with its own `Chart.yaml`, `values.yaml`, and templates.
   The values for config-store itself, such as `image` and `resources`, apply only to its own templates. The `postgresql` key passes values to the dependency, and exercises 03 and 04 explain how.

## Conclusion

In this exercise, we added PostgreSQL 16.2.2 as a dependency of config-store, downloaded it with `helm dependency update`, rebuilt it from `Chart.lock` with `helm dependency build`, and pointed its image to `bitnamilegacy`.
Exercise 03 passes values from a parent chart to its dependencies.
