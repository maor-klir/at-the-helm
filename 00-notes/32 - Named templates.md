#helm #kubernetes #templating

# Named templates

A chart repeats the same pieces in many places: the resource name in every object, and the same labels in a Deployment's metadata, its selector, its Pod template, and a Service's selector.
Repeated by hand, one missed copy still renders and installs without an error: a Service whose selector no longer matches the Pod labels selects no Pods and routes no traffic.

A named template defines such a piece once, and `include` renders it wherever it's needed.

## Defining a named template

Helm's named templates guide describes the action: *"The `define` action allows us to create a named template inside of a template file."*
A `define` takes the template's name as a string and ends with `end`:

```yaml
{{- define "go-templating-deep-dive.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
```

Named templates usually live in `templates/_helpers.tpl`.
A file whose name starts with an underscore isn't rendered as a manifest, and the templates it defines are available to every other template (see **22 - Helm chart structure**).

**Template names are global:** a chart and its subcharts share one set of names, and *"if two templates are declared with the same name the last occurrence will be the one that is used."*
So names start with the chart's name: *"A popular naming convention is to prefix each defined template with the name of the chart: `{{ define "mychart.labels" }}`."*
The dots after the prefix are only part of the string.

The `helm create` scaffold defines six: `<chart>.name`, `<chart>.fullname`, `<chart>.chart`, `<chart>.labels`, `<chart>.selectorLabels`, and `<chart>.serviceAccountName`.

## Including a named template

`include` takes the template's name and the value to use as its dot, and returns the rendered text:

```yaml
metadata:
  name: {{ include "go-templating-deep-dive.fullname" . }}
  labels:
    {{- include "go-templating-deep-dive.selectorLabels" . | nindent 4 }}
```

**`include` rather than `template`:** Go template syntax has a `template` action for the same job, but *"Because `template` is an action, and not a function, there is no way to pass the output of a `template` call to other functions; the data is simply inserted inline."*

The guide's advice follows: *"It is considered preferable to use `include` over `template` in Helm templates simply so that the output formatting can be handled better for YAML documents."*

With `template`, a pipe applies to its argument instead of its output.
`{{ template "go-templating-deep-dive.selectorLabels" . | nindent 4 }}` passes `.` to `nindent`, and the render fails with `wrong type for value; expected string; got common.Values`.

**A named template's output is text:** labels written as YAML need no `toYaml`, but their indentation has to match each place they're included.
In a Deployment, that's `nindent 4` under `metadata.labels`, `nindent 6` under `spec.selector.matchLabels`, and `nindent 8` under the Pod template's `labels` (see **31 - Functions and pipelines**).

**A named template can also output nothing:** a validator checks its context and stops the render with `fail`, and its `include` sits on a line of its own (see **36 - Validating values**).

## The context

The second argument of `include` becomes the dot inside the named template.
The guide says so for `template` calls, and `include` works the same: *"When a named template (created with `define`) is rendered, it will receive the scope passed in by the `template` call."*

Passing `.` gives the template everything: `.Values`, `.Release`, `.Chart`, and the rest.
A narrower value is allowed, *"We could just as easily pass `.Values` or `.Values.favorite` or whatever scope we want."*, but then the template sees only that.

`{{ include "go-templating-deep-dive.fullname" .Values }}` fails inside the helper, at `<.Release.Name>`, with `nil pointer evaluating interface {}.Name`: inside it, `.Release.Name` now means `.Values.Release.Name`.

`$` follows the context too: inside a named template, `$` is the second argument of `include`, not the chart's top-level object (see **35 - The dot and with blocks**).

## Building a name

The name helper builds the name with `printf`, so the result can be piped on:

- **`trunc 63`:** keeps the name within the 63 characters Kubernetes allows for many object names.
- **`trimSuffix "-"`:** removes a dash the cut may leave at the end.

With a 48-character release name and the chart `go-templating-deep-dive`, the cut lands right after `go-templating-`, so the name becomes `<release name>-go-templating`, 62 characters.
Release names longer than 53 characters are rejected before rendering, even by `helm template` (see **24 - Values and release information in a chart**).

The scaffold's `fullname` helper also drops the chart name when the release name already contains it, so a release `local-demo` of a chart `demo` gets objects named `local-demo`.

## Labels and selector labels

One named template for the labels keeps every selector consistent with the Pod labels it has to match: a Service including the same `selectorLabels` as its Deployment's Pod template always selects that Deployment's Pods.

**Selector labels are the set to keep stable:** a Deployment's `spec.selector` can't change after it's created, so a later change to the selector labels makes `helm upgrade` fail for releases already installed (see **01 - The role of Helm in Kubernetes**).
The scaffold therefore keeps two named templates: `selectorLabels` for the selectors, and `labels`, which includes `selectorLabels` and adds the labels that may change:

```yaml
{{- define "backend-app.labels" -}}
helm.sh/chart: {{ include "backend-app.chart" . }}
{{ include "backend-app.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
```

A named template can include another one, as `labels` does here.
`app.kubernetes.io/version` changes with every new `appVersion`, which is why it belongs in `labels` and never in `selectorLabels`.

## Verify

From `03-go-templating-deep-dive/03-if-statements`, our `go-templating-deep-dive` chart includes the name and labels templates in its Deployment and Service:

```bash
helm template my-app go-templating-deep-dive --set service.enabled=true | grep -E '^kind|  name:|app:|release:'
```

Both objects are named `my-app-go-templating-deep-dive`, and the Deployment's three label blocks and the Service's labels and selector all render `app: go-templating-deep-dive` and `release: my-app`.

A long release name shows the truncation:

```bash
helm template $(printf 'r%.0s' {1..48}) go-templating-deep-dive -s templates/deployment.yaml | grep -m1 '  name:'
```
