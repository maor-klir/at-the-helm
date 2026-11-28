#helm #subcharts #dependencies

# Enabling subcharts with conditions and tags

A dependency in `Chart.yaml` can be switched on and off from the values, without removing it from the list.
The Charts documentation: *"All charts are loaded by default. If `tags` or `condition` fields are present, they will be evaluated and used to control loading for the chart(s) they are applied to."*

A disabled subchart is left out of the render completely: none of its templates produce objects, and its named templates can't be included either.

## The example charts

The examples below use `config-store`, the chart of a small key-value store application (see **41 - The config-store application**), with two subcharts in its `charts/` directory.
Bitnami's PostgreSQL chart 16.2.2 runs its database.
`demo-subchart`, created with `helm create` and cut down to one ConfigMap, renders a single value, `customValue`, whose own default is `hello from demo-subchart`.

With its default values, the PostgreSQL chart renders 7 templates: a StatefulSet, two Services, a Secret, a ServiceAccount, a NetworkPolicy, and a PodDisruptionBudget.

## Conditions

A condition is a path into the parent's values. The dependency best practices prefer the form `somechart.enabled`, *"Where `somechart` is the chart name of the dependency."*

For PostgreSQL in `config-store`:

```yaml
dependencies:
  - name: postgresql
    version: '16.2.2'
    repository: 'https://charts.bitnami.com/bitnami'
    condition: postgresql.enabled
```

The Charts documentation: *"If this path exists in the top parent's values and resolves to a boolean value, the chart will be enabled or disabled based on that boolean value."*
With `postgresql.enabled: false` in `config-store`'s values, the render drops all 7 PostgreSQL templates; `--set postgresql.enabled=false` does the same.

**A missing path changes nothing:** *"Only the first valid path found in the list is evaluated and if no paths exist then the condition has no effect."*
Without `enabled` in the values, PostgreSQL still renders, so the parent's `values.yaml` should set the key to document the switch.

**The value has to be a boolean:** `--set-string postgresql.enabled=false` passes the string `"false"`, and Helm ignores the condition with `level=WARN msg="returned non-bool value" path=postgresql.enabled chart=postgresql`.

**Several paths aren't combined:** a condition can list paths separated by commas, such as `subchart1.enabled,global.subchart1.enabled`, and the first one that exists in the values decides.
With `condition: redis.enabled,postgresql.enabled`, `--set postgresql.enabled=false` disabled PostgreSQL, since `redis.enabled` didn't exist; adding `--set redis.enabled=true` enabled it again.

**A shared path switches several charts:** with `condition: global.database.enabled` on both dependencies, `--set global.database.enabled=false` disabled PostgreSQL and `demo-subchart` together, and `true` enabled both.
The best practices ask for tags in this case: *"When multiple subcharts (dependencies) together provide an optional or swappable feature, those charts should share the same tags."*
A chart can carry several tags, while a shared condition path, once set, overrides any tags as well.

## Tags

Tags group dependencies so one value switches several of them:

```yaml
dependencies:
  - name: postgresql
    tags:
      - database
      - performance
  - name: demo-subchart
    tags:
      - performance
```

The values set them under a top-level `tags` key, such as `tags.performance: false`.
The resolution rule: *"Tags are evaluated as 'if any of the chart's tags are true then enable the chart'."*

| `tags` in the values | `postgresql` | `demo-subchart` |
|---|---|---|
| `database: true`, `performance: true` | enabled | enabled |
| `database: true`, `performance: false` | enabled | disabled |
| `performance: false` only | disabled | disabled |
| no `tags` key | enabled | enabled |

**A chart needs a `false` tag and no `true` one to be disabled:** in the third row, `postgresql`'s `database` tag is unset, and its `performance` tag alone disables it.

**Tags work only at the top level:** *"The `tags:` key in values must be a top level key. Globals and nested `tags:` tables are not currently supported."*
`--set global.tags.performance=false` left both subcharts enabled.

## Conditions and tags together

*"Conditions (when set in values) always override tags."*
This works in both directions:
- with `condition: demo-subchart.enabled` added to `demo-subchart`, `--set tags.performance=false --set demo-subchart.enabled=true` still rendered its ConfigMap;
- with `condition: postgresql.enabled` and `tags: [database]` on PostgreSQL, `--set tags.database=true --set postgresql.enabled=false` left out all 7 of its templates.

Both are read only from the parent chart that installs the release: *"Tags and conditions values must be set in the top parent's values."*

## Effects beyond the render

**An upgrade deletes the disabled subchart's objects:** Helm's source describes its update step as one that *"deletes resources from the current configuration that are not present in the target configuration"*.
The PostgreSQL PersistentVolumeClaim stays, because the StatefulSet created it, not the chart (see **12 - Uninstalling releases and persistent data**).

**The parent can't include the disabled subchart's templates:** with `demo-subchart` disabled, an `include "demo-subchart.fullname"` in `config-store` fails with `template: no template "demo-subchart.fullname" associated with template "gotpl"` (see **32 - Named templates**).

**The lock file covers both fields:** `condition` and `tags` are part of the dependency entries, so adding either one makes `helm dependency build` fail until `helm dependency update` writes a new `Chart.lock` (see **51 - Chart dependencies**).

**An optional dependency needs a replacement:** `config-store` builds its `DB_URL` from the PostgreSQL chart's values, so a condition on PostgreSQL is useful only together with a value for an external database's URL.
Without one, the dependency stays mandatory, and no condition or tag belongs on it.
