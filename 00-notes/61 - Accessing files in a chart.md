#helm #templating #files

# Accessing files in a chart

A chart can carry files that aren't templates, such as configuration files, and its templates read them through `.Files`.
The accessing files guide describes the purpose: to *"inject its contents without sending the contents through the template renderer."*

Files from outside the chart reach the templates only as values, through `--set-file`.

## What `.Files` contains

The accessing files guide lists what's out of reach: *"Files in `templates/` cannot be accessed."*, *"Files excluded using `.helmignore` cannot be accessed."*, and files outside the chart, *"including those of the parent"*.

**`Chart.yaml` and `values.yaml` aren't in `.Files` either:** in a chart with `files/`, `README.md`, and `LICENSE`, ranging over `.Files` listed only those, without `Chart.yaml`, `values.yaml`, or `values.schema.json`.
Helm's source explains it: the chart loader stores those in their own fields, and every other file outside `templates/` in `Files`.

**A path that can't be read returns nothing:**

| `.Files.Get` path | Result |
|---|---|
| `files/missing.properties`, a file that doesn't exist | `""` |
| `templates/_helpers.tpl` | `""` |
| a file listed in `.helmignore` | `""` |
| `../outside.properties` | `""` |

None of them is an error, so a typo in a path renders an empty value.

**A non-template file can't live under `templates/`:** Helm renders every file there as a manifest. A shell script at `templates/tests/run.sh` failed the render, before `.Files.Get` mattered:

```text
Error: YAML parse error on q/templates/tests/run.sh: error unmarshaling JSON: while decoding JSON: json: cannot unmarshal string into Go value of type util.SimpleHead
```

`helm lint` rejects it by its extension, `file extension '.sh' not valid. Valid extensions are .yaml, .yml, .tpl, or .txt`, a rule in Helm's source (`validateAllowedExtension`). Moved to `files/run.sh`, the script loads with `.Files.Get "files/run.sh"`, and the lint passes.

**The files are part of the chart:** the guide warns, *"Charts must be smaller than 1M because of the storage limitations of Kubernetes objects."*
A client-side dry run's release record lists them under the chart's `files`, so every revision of the release stores them (see **22 - Helm chart structure**).

## One file: `.Files.Get`

`.Files.Get` takes a path from the chart's root and returns the file's contents as a string. Under a block scalar, the indentation has to match:

| Template line, under `application.properties: \|-` | Value |
|---|---|
| `{{ .Files.Get "files/application.properties" \| nindent 4 }}` | `'\nserver.port=8080\n\nlogging.level.root=INFO'` |
| `{{- .Files.Get "files/application.properties" \| nindent 4 }}` | `'server.port=8080\n\nlogging.level.root=INFO'` |
| `{{ .Files.Get "files/application.properties" \| indent 4 }}` | `'server.port=8080\n\nlogging.level.root=INFO'` |

`nindent` starts with a newline, so on a line of its own it adds a blank first line to the value; `{{-` removes the newline before the action, and `indent` adds none (see **31 - Functions and pipelines**).

## Several files: `.Files.Glob`

*"`.Glob` returns a `Files` type, so you may call any of the `Files` methods on the returned object."* Ranging over it gives each file's path and contents:

```yaml
data:
{{- range $path, $_ := .Files.Glob "files/*.properties" }}
  {{ base $path }}: |-
{{ $.Files.Get $path | indent 4 }}
{{- end }}
```

**Inside the loop, the dot is a file's contents:** `.Files.Get` there fails with `can't evaluate field Files in type []uint8`, and `$.Files.Get` reaches the top-level object (see **35 - The dot and with blocks**).

**`base` makes the keys valid:** without it, the keys are paths such as `files/dev.properties`, and the API server rejects them with `a valid config key must consist of alphanumeric characters, '-', '_' or '.'`.
`base` is one of the path functions the guide describes, *"Helm imports many of the functions from Go's path package for your use."*, together with `dir`, `ext`, `isAbs`, and `clean`.

The guide links its patterns to the `gobwas/glob` library, and Helm's source compiles them with `/` as the separator:

| Pattern | Matched |
|---|---|
| `files/*.properties` | the files directly in `files/` |
| `files/**.properties` | those, and the ones in subfolders of `files/` |
| `**.properties` | every `.properties` file in the chart |
| `*.properties` | only those at the chart's root |
| `files/{dev,prod}.properties` | `dev.properties` and `prod.properties` |

`range` over the result lists the files in alphabetical order.

## `.AsConfig` and `.AsSecrets`

The guide offers two methods for the common case: *"It is very common to want to place file content into both ConfigMaps and Secrets, for mounting into your pods at run time."*

```yaml
data:
{{ (.Files.Glob "files/*.properties").AsConfig | indent 2 }}
```

`.AsConfig` renders the same entries as the loop above, and `.AsSecrets` renders each file in base64, as a Secret's `data` requires.
Both key each entry by the file's base name (from Helm's source, `path.Base`), so the template needs no `base`.

**Files with the same name collide:** with `files/**.properties`, a second `dev.properties` in `files/nested/` replaced the first, and the ConfigMap had a single `dev.properties` key.

**`.AsSecrets` doesn't make the data secret:** the files travel with every copy of the chart, and base64 is an encoding.
The Kubernetes documentation adds: *"Kubernetes Secrets are, by default, stored unencrypted in the API server's underlying data store (etcd)."*

## Files from outside the chart: `--set-file`

The guide: *"To supply the contents of a file outside the chart as a value, use `--set-file`"*.
`--set-file config=./config.ini` stores the file's contents as a string in `.Values.config`:

```yaml
data:
  config.ini: |-
    {{- .Values.config | nindent 4 }}
```

| | `.Files` | `--set-file` |
|---|---|---|
| Where the file comes from | packaged with the chart, the same in every installation | the command line, so it can differ per installation |
| How a template reads it | `.Files.Get "files/…"` | `.Values.<key>` |
| Where the release stores it | the chart's `files` | the user-supplied values, shown by `helm get values` |
| On `helm upgrade` | comes with the chart version installed | kept only by `--reuse-values` or `--reset-then-reuse-values`, or by passing it again (see **14 - Upgrading releases**) |

A client-side dry run with `--set-file config=ext.properties` showed the file's contents in the release record's user-supplied values, `{'config': 'server.port=9090\n'}`.
Neither way keeps a secret out of the release record, so secrets belong in Secrets created outside the chart (see **42 - From Compose to a Helm chart**).

## Verify

From `06-advanced-topics/03-configmap-secret-utilities`, the chart builds a ConfigMap and a Secret from the same four files, and the API server accepts both:

```bash
helm template accessing-files | grep -E '^kind|^  [a-z]+\.properties: \|'
helm template accessing-files | kubectl -n default apply --dry-run=server -f -
```

```text
kind: Secret
kind: ConfigMap
  another.properties: |-
  application.properties: |-
  dev.properties: |-
  prod.properties: |-
secret/release-name-accessing-files created (server dry run)
configmap/release-name-accessing-files created (server dry run)
```
