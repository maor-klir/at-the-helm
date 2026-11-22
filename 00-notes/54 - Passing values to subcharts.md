#helm #subcharts #values

# Passing values to subcharts

A parent chart configures its subcharts through its own `values.yaml`: under each subchart's name for that subchart, and under `global` for every chart below it.
The Subcharts and Global Values guide starts from the subchart's side: *"A subchart is considered "stand-alone", which means a subchart can never explicitly depend on its parent chart."*

Two rules follow from it: *"For that reason, a subchart cannot access the values of its parent."* and *"A parent chart can override values for subcharts."*

## Values under the subchart's name

A top-level key named after a dependency goes to that dependency: *"Any directives inside of the `mysubchart` section will be sent to the `mysubchart` chart."*
The subchart's templates keep their own paths: *"So for the `mysubchart` templates, only values specifically for `mysubchart` will be available in `.Values`."*

`config-store`'s `values.yaml` has a section for each of its subcharts:

```yaml
postgresql:
  image:
    repository: bitnamilegacy/postgresql

demo-subchart:
  customValue: 'hello from config-store'
```

`demo-subchart`'s ConfigMap reads `{{ .Values.customValue }}` and renders `hello from config-store`.
The same key at the parent's top level doesn't reach it, and the subchart's own default, `hello from demo-subchart`, stays.

**The parent's section is merged over the subchart's defaults:** setting only `postgresql.image.repository` keeps the chart's `registry` and `tag`, and the image renders as `docker.io/bitnamilegacy/postgresql:17.2.0-debian-12-r0`.
`--set` uses the same paths, such as `postgresql.auth.database` (see **13 - Overriding chart values**).

**A section reaches only its own subchart:** with `postgresql.fullnameOverride: my-new-name`, the PostgreSQL objects are renamed, while `{{ .Values.fullnameOverride }}` in `demo-subchart` renders nothing.
The rendered line is `test-value2:` with no value, which YAML reads as null.

**A packaged dependency changes only through values:** its templates are inside the archive in `charts/`, and `helm dependency update` replaces that archive with the downloaded one (see **51 - Chart dependencies**).

## Global values

The guide defines them: *"Global values are values that can be accessed from any chart or subchart by exactly the same name."*
The Charts documentation shows how: Helm copies the parent's `global` section into each subchart's values, *"Effectively, the values file above is regenerated like this:"*

```yaml
global:
  defaultStorageClass: 'my-custom-storageclass'

postgresql:
  global:
    defaultStorageClass: 'my-custom-storageclass'
  image:
    repository: bitnamilegacy/postgresql

demo-subchart:
  global:
    defaultStorageClass: 'my-custom-storageclass'
  customValue: 'hello from config-store'
```

**A template has to read `.Values.global`:** *"Globals require explicit declaration. You can't use an existing non-global as if it were a global."*
In `demo-subchart`, `{{ .Values.global.defaultStorageClass }}` renders `my-custom-storageclass`, while `{{ .Values.defaultStorageClass }}` renders nothing.

The guide adds: *"Globals are useful for passing information like this, though it does take some planning to make sure the right templates are configured to use globals."*
PostgreSQL 16.2.2 reads only a few keys from `global`: `imageRegistry`, `imagePullSecrets`, `defaultStorageClass`, the deprecated `storageClass`, `postgresql.auth`, `postgresql.service.ports`, and `compatibility`.

**Globals go down, not up:** *"There is no way for a subchart to influence the values of the parent chart."*
A `global.fromSub` key in `demo-subchart`'s `values.yaml` reached the subchart's own templates, and rendered nothing in a template of `config-store`.

**The parent's globals win:** *"Also, global variables of parent charts take precedence over the global variables from subcharts."*
With `global.defaultStorageClass: 'subchart-default'` in `demo-subchart`'s `values.yaml`, its ConfigMap still showed the parent's `my-custom-storageclass`.

## Global or local: the chart decides

Some of PostgreSQL's global keys repeat one of its own values, such as `global.postgresql.auth.database` and `auth.database`.
Which one wins is written in the chart's templates, and differs from value to value:

| Value | Order in PostgreSQL 16.2.2's templates | Tested with both set |
|---|---|---|
| Database name | the `postgresql.v1.database` helper: `global.postgresql.auth.database`, then `auth.database` | `global-db` over `local-db` |
| User password | `secrets.yaml`: `coalesce .Values.global.postgresql.auth.password .Values.auth.password …` | not printed |
| StorageClass | the `common.storage.class` helper: `global.storageClass`, then `primary.persistence.storageClass`, then `global.defaultStorageClass` | `local-path` over `my-custom-storageclass` |

The function reference describes `coalesce`: *"The `coalesce` function takes a list of values and returns the first non-empty one."*
For our own charts, the same choice applies to every key that has both a global and a local form, and the chart's values documentation is where to state it.

## Verify

From `05-chart-dependencies-subcharts/04-global-values/subcharts/config-store`, the parent's section and its global value reach both subcharts:

```bash
helm template . | grep -E 'test-(global-)?value|storageClassName|image: .*postgresql'
```

```text
  test-value: hello from config-store
  test-global-value: my-custom-storageclass
          image: docker.io/bitnamilegacy/postgresql:17.2.0-debian-12-r0
        storageClassName: my-custom-storageclass
```
