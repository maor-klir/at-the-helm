# Using global values

## Overview

In this exercise, we'll set a value under `global` in config-store's `values.yaml`, read it from both subcharts, and see that each chart decides whether a global value or its own value wins.
Here's a quick summary of the main steps:

1. Find the global values that the PostgreSQL chart accepts.
2. Set `global.defaultStorageClass` in the parent, and see it in the PostgreSQL StatefulSet.
3. Read the same value in `demo-subchart`, with and without `.global`.
4. Compare which value wins for a database name and for a StorageClass.

## Step-by-step guide

The chart in `subcharts/config-store/` is the end state of this exercise, and continues from exercise 03's chart.
To build it yourself, copy exercise 03's `subcharts` directory into an empty directory, and run the steps there. Run the commands from `config-store/`.

1. **Find the chart's global values:**

   The course opens the PostgreSQL chart on Artifact Hub, which shows the values of its latest version. The archive in `charts/` has the values of 16.2.2:

   ```bash
   helm show values charts/postgresql-16.2.2.tgz | grep -n -E '^global:|^  [a-zA-Z]+:|^## @section Common'
   ```

   ```text
   7:global:
   10:  imageRegistry: ""
   16:  imagePullSecrets: []
   20:  defaultStorageClass: ""
   21:  storageClass: ""
   22:  postgresql:
   49:  compatibility:
   56:## @section Common parameters
   ```

   The `global` block ends at line 56. The chart reads these few keys from `global`; every other value, such as `auth` or `primary`, it reads only from its own section.

2. **Set a global value in the parent:**

   Add to the end of config-store's `values.yaml`:

   ```yaml
   global:
     defaultStorageClass: 'my-custom-storageclass'
   ```

   ```bash
   helm template . --show-only charts/postgresql/templates/primary/statefulset.yaml | grep storageClassName
   ```

   ```text
           storageClassName: my-custom-storageclass
   ```

   The PostgreSQL StatefulSet's `volumeClaimTemplates` now name the StorageClass; without the value, the field is left out, and the cluster's default StorageClass applies.
   k3d-argocd has only `local-path`, so this value is for rendering; exercise 07 removes it before the install.

3. **Read the global value in `demo-subchart`:**

   In `charts/demo-subchart/templates/configmap.yaml`, replace the `test-value2` line:

   ```yaml
     test-global-value: {{ .Values.global.defaultStorageClass }}
   ```

   ```bash
   helm template . --show-only charts/demo-subchart/templates/configmap.yaml
   ```

   The ConfigMap now has `test-global-value: my-custom-storageclass`. The Subcharts and Global Values guide: *"Global values are values that can be accessed from any chart or subchart by exactly the same name."*

4. **Read it without `.global`:**

   Change the line to `{{ .Values.defaultStorageClass }}`, and render again. `test-global-value:` now has no value: the subchart's `.Values` has the key only under `global`.
   The same guide: *"Globals require explicit declaration. You can't use an existing non-global as if it were a global."*

   Change the line back to `.Values.global.defaultStorageClass`. A subchart uses a global value only where its templates read `.Values.global`, which is why PostgreSQL accepts only the keys from step 1.

5. **Compare which value wins:**

   Several of PostgreSQL's global keys repeat one of its own values, such as `global.postgresql.auth.database` and `auth.database`. The chart's templates decide which one wins:

   ```bash
   helm template . --set postgresql.auth.database=local-db --set global.postgresql.auth.database=global-db \
     --show-only charts/postgresql/templates/primary/statefulset.yaml | grep -A1 POSTGRES_DATABASE
   helm template . --set postgresql.primary.persistence.storageClass=local-path \
     --show-only charts/postgresql/templates/primary/statefulset.yaml | grep storageClassName
   ```

   ```text
               - name: POSTGRES_DATABASE
                 value: "global-db"
           storageClassName: local-path
   ```

   | Value | Order in the chart's templates | Result |
   |---|---|---|
   | Database name | the `postgresql.v1.database` helper: `global.postgresql.auth.database`, then `auth.database` | the global value wins |
   | User password | `secrets.yaml`: `coalesce .Values.global.postgresql.auth.password .Values.auth.password …` | the global value wins |
   | StorageClass | the `common.storage.class` helper: `global.storageClass`, then `primary.persistence.storageClass`, then `global.defaultStorageClass` | the chart's own value wins over `global.defaultStorageClass` |

   The function reference describes `coalesce`: *"The `coalesce` function takes a list of values and returns the first non-empty one."*
   The order is the chart author's choice, so the chart's values documentation is where to check it. `global.storageClass` is deprecated in favour of `global.defaultStorageClass`.

## Conclusion

In this exercise, we set `global.defaultStorageClass` in config-store's `values.yaml`, read it from the PostgreSQL chart and from `demo-subchart`, and saw that each chart decides whether its global or its own value wins.
Exercise 05 shares named templates between a parent chart and its subcharts.
