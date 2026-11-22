# Enabling subcharts conditionally

## Overview

In this exercise, we'll turn config-store's subcharts on and off from its values, first with a `condition` on the PostgreSQL dependency, then with `tags` shared by both subcharts.
Here's a quick summary of the main steps:

1. Add `condition: postgresql.enabled` to the PostgreSQL dependency, and toggle it from the values.
2. Replace the condition with a `database` tag.
3. Add a `performance` tag to both subcharts, and combine the two tags.
4. Undo the changes.

## Step-by-step guide

The chart doesn't change in this exercise: the course undoes its changes at the end, so exercise 04's chart is both the start and the end state.
Copy exercise 04's `subcharts` directory into an empty directory, and run the commands from `config-store/`. The count of PostgreSQL templates in the render shows whether the subchart is enabled:

```bash
helm template . | grep -c '^# Source: config-store/charts/postgresql/'
```

It prints `7` while PostgreSQL is enabled, and `0` when it's disabled.

1. **Add a condition:**

   In `Chart.yaml`, add `condition` to the PostgreSQL dependency:

   ```yaml
     - name: postgresql
       version: '16.2.2'
       repository: 'https://charts.bitnami.com/bitnami'
       condition: postgresql.enabled
   ```

   Then add `enabled: false` to the `postgresql:` block in `values.yaml`:

   ```yaml
   postgresql:
     enabled: false
     image:
       repository: bitnamilegacy/postgresql
   ```

   The count drops to `0`: the render keeps config-store's own four objects and `demo-subchart`'s ConfigMap. With `enabled: true`, or with `--set postgresql.enabled=true`, it's `7` again.

   **The path has to exist and hold a boolean:** without `enabled` in the values, the condition has no effect and PostgreSQL renders.
   A string such as `--set-string postgresql.enabled=false` is ignored too, with a warning: `level=WARN msg="returned non-bool value" path=postgresql.enabled chart=postgresql`.

   On an upgrade, Helm deletes the objects that the new render no longer contains. The database's PersistentVolumeClaim isn't one of them, because the StatefulSet created it (see **12 - Uninstalling releases and persistent data**).

2. **Replace the condition with a tag:**

   In `Chart.yaml`, replace `condition: postgresql.enabled` with a tag:

   ```yaml
       tags:
         - database
   ```

   Remove `enabled` from the `postgresql:` block, and add a top-level `tags` key to `values.yaml`:

   ```yaml
   tags:
     database: true
   ```

   The count is `7`; with `database: false`, it's `0`.

3. **Share a tag between subcharts:**

   Add a second tag, `performance`, to the PostgreSQL dependency, and give `demo-subchart` the same tag:

   ```yaml
     - name: postgresql
       version: '16.2.2'
       repository: 'https://charts.bitnami.com/bitnami'
       tags:
         - database
         - performance
     - name: demo-subchart
       version: '0.1.0'
       tags:
         - performance
   ```

   | `tags` in `values.yaml` | PostgreSQL | `demo-subchart` |
   |---|---|---|
   | `database: true`, `performance: true` | rendered | rendered |
   | `database: true`, `performance: false` | rendered | not rendered |
   | `performance: false` only | not rendered | not rendered |
   | no `tags` key | rendered | rendered |

   The Charts documentation states the rule: *"Tags are evaluated as 'if any of the chart's tags are true then enable the chart'."* A chart whose tags are all unset stays enabled, and a `false` tag disables a chart that has no `true` one.
   A condition that resolves to a boolean wins over the tags, and tags work only as a top-level `tags` key: `global.tags.performance=false` has no effect (see **55 - Enabling subcharts with conditions and tags**).

4. **Keep the lock file in mind:**

   `condition` and `tags` are part of the dependency entries, so `Chart.lock` is now out of sync. `helm template` and `helm lint` don't check it, but `helm dependency build` fails until `helm dependency update` writes a new lock (see **51 - Chart dependencies**).

5. **Undo the changes:**

   Remove the `tags` from both dependencies in `Chart.yaml`, and the `tags` key from `values.yaml`.

   **A disabled dependency has to be optional for the application:** the course keeps PostgreSQL mandatory, because config-store needs a database. Exercise 07 builds `DB_URL` from the PostgreSQL chart's values, so an optional PostgreSQL would also need a value for an external database's URL.

## Conclusion

In this exercise, we enabled and disabled config-store's subcharts with a `condition` and with `tags`, and saw how a shared tag and a missing value change the result.
Exercise 07 configures the PostgreSQL subchart and connects config-store to it.
