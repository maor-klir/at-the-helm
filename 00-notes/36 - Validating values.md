#helm #kubernetes #templating

# Validating values

Users override a chart's values, and a missing or invalid value can render a manifest that the API server rejects, or one that it accepts and that runs with the wrong settings.
A chart can check its values instead, and stop with a message that names the value: with the `required` and `fail` functions, with validators built from named templates, and with a `values.schema.json` that Helm checks before rendering.

The examples come from `go-templating-deep-dive`, a chart written from scratch to try the Helm template language: a Deployment of nginx Pods, with a `securityContext` value for the Pod's user and group, one Service per entry of the `services` map, and `templates/validation.yaml`, a template that renders nothing and only checks the values.

Its `templates/sandbox.yaml` holds template experiments and isn't a Kubernetes object, so the chart is only rendered with `helm template`.

## `required`

Helm's function list defines it: *"If `.Bar` is empty or not defined (see default on how this is evaluated), the template will not render and will return the error message supplied instead."*

```yaml
{{- $_ := required "securityContext.runAsUser is required when setting securityContext and enabled is true" .Values.securityContext.runAsUser }}
```

A missing value stops the render with the message, prefixed by the file, line, and column: `Error: execution error at (go-templating-deep-dive/templates/validation.yaml:2:10): securityContext.runAsUser is required when setting securityContext and enabled is true`.

**`required` returns the value it checks:** on a line of its own, `{{ required … }}` prints the value into the manifest, so a check that only guards gets assigned to a variable nobody uses.
An action that declares a variable outputs nothing (see **34 - Variables and scope**).

**It accepts more than its description suggests:** in Helm 4.3, `required` stops the render only for a missing or `null` value and for an empty string.
`0`, `false`, `[]`, and `{}` pass, although they count as empty for `default`, so a value that must not be `0` needs a `fail` check.

**`helm lint` doesn't report a missing required value:** with `--set securityContext.runAsUser=null`, the lint ends with `1 chart(s) linted, 0 chart(s) failed`, while `helm template` stops.

## `fail`

The function list defines it: *"Unconditionally returns an empty `string` and an `error` with the specified text. This is useful in scenarios where other conditionals have determined that template rendering should fail."*
`fail` therefore sits inside an `if` whose condition describes the invalid value:

```yaml
{{- if le (int .Values.securityContext.runAsUser) 0 -}}
{{- fail "Invalid value for: securityContext.runAsUser. Containers cannot be run as root users. Please provide a uid greater than 0" -}}
{{- end -}}
```

**Numbers need `int` before a comparison:** a number from `values.yaml` is a `float64`, and `eq .Values.securityContext.runAsUser 0` fails with `incompatible types for comparison: float64 and int` (see **33 - Conditionals and loops**).
`int` also turns a string that isn't a number into `0`.

**The condition has to match the message:** `int .Values.securityContext.runAsUser | eq 0` rejects only `0`, and `-1` passes; `le … 0` rejects both.

The message is a single string.
`\n` starts new lines, and for tools that parse the output, `fail (dict "error" "securityContext.runAsUser" "message" "…" | toJson)` prints JSON; without the parentheses, `fail` receives five arguments and the render stops with `wrong number of args for fail: want 1 got 5`.

## Where checks live

| Place | Behavior |
|---|---|
| On the line that uses the value: `runAsUser: {{ required "…" .runAsUser }}` | the check sits next to the value, and its result is the value |
| In a template that renders nothing, such as `templates/validation.yaml` | all checks in one place; with valid values, the file adds no document |
| At the top level of `_helpers.tpl` | the checks never run |

Helm's named templates guide explains the last row: *"files whose name begins with an underscore (`_`) are assumed to _not_ have a manifest inside. These files are not rendered to Kubernetes object definitions, but are available everywhere within other chart templates for use."*
Only the named templates defined in such a file are used.

**`and` guards nested values:** `if and .Values.securityContext .Values.securityContext.enabled` is safe when `securityContext` is missing, because `and` stops early: *"Evaluation proceeds through the arguments left to right and returns when the result is determined."*

**`dig` reads a nested value with a fallback:** the function list describes it: *"The `dig` function traverses a nested set of dicts, selecting keys from a list of values. It returns a default value if any of the keys are not found at the associated dict."*

`dig "securityContext" "enabled" false .Values.AsMap` returns `false` when either key is missing.
It needs `.Values.AsMap`: with plain `.Values`, it fails with `interface {} is common.Values, not map[string]interface {}`.

## Validators as named templates

A validator is a named template that checks its context and calls `fail` when the value is invalid (see **32 - Named templates**).
A comment above the `define` documents what the context has to be:

```yaml
{{/*Expects an integer or string to be passed as the context*/}}
{{- define "go-templating-deep-dive.validators.portRange" -}}
{{- $sanitizedPort := int . -}}
{{- if or (lt $sanitizedPort 1) (gt $sanitizedPort 65535) -}}
{{- fail "Error: Ports must always be between 1 and 65535." -}}
{{- end -}}
{{- end -}}
```

**A validator either returns the value or only checks:** called as `port: {{ include "…portRange" .port }}`, a validator that outputs nothing leaves `port:` empty.
Ending it with `{{- . }}` returns the port, so the check and the value share one `include`.

A validator that only checks is included on a line of its own, such as the first line of a `range` loop, with the whole object as its context.
It can include other validators, as a Service validator includes the port validator with `.port`, and add its own checks:

```yaml
{{- $allowedSvcTypes := list "ClusterIP" "NodePort" -}}
{{- if not (has .type $allowedSvcTypes) -}}
{{- fail (printf "Invalid service type %s. Supported values are: %s" .type (join ", " $allowedSvcTypes)) -}}
{{- end -}}
```

`join ", "` turns the list into `ClusterIP, NodePort`; with `%s` alone, the message prints the list as `[ClusterIP NodePort]`.
An error inside a validator is reported at the `include` that called it, such as `service.yaml:2:3`.

## `values.schema.json`

Helm also validates values against a JSON Schema: *"Sometimes, a chart maintainer might want to define a structure on their values. This can be done by defining a schema in the `values.schema.json` file."*

The same Charts documentation lists when it runs, *"Validation occurs when any of the following commands are invoked:"* `helm install`, `helm upgrade`, `helm lint`, and `helm template`, and adds: *"the schema is applied to the final `.Values` object, and not just to the `values.yaml` file."*

The port and type rules of the Service validator, written as a schema:

```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "services": {
      "type": "object",
      "additionalProperties": {
        "type": "object",
        "required": ["type", "port"],
        "properties": {
          "type": { "enum": ["ClusterIP", "NodePort"] },
          "port": { "type": "integer", "minimum": 1, "maximum": 65535 }
        }
      }
    }
  }
}
```

With `--set services.svc1.port=99999`, both `helm template` and `helm lint` stop before rendering:

```text
Error: values don't meet the specifications of the schema(s) in the following chart(s):
go-templating-deep-dive:
- at '/services/svc1/port': maximum: got 99,999, want 65,535
```

**Schema or template checks:** a schema describes the values alone, reports every violation with its path, and fails `helm lint`.
A template check can also use the release, the chart, and computed values, such as the length of a name built from the release name, and words its own message.

## Verify

From `03-go-templating-deep-dive/11-implementing-custom-validators`, our `go-templating-deep-dive` chart checks its values in `templates/validation.yaml` and in the Service validators:

```bash
helm template go-templating-deep-dive --set services.svc1.type=ExternalName
helm template go-templating-deep-dive --set securityContext.runAsUser=0
helm template go-templating-deep-dive --set securityContext.runAsUser=null
```

```text
Error: execution error at (go-templating-deep-dive/templates/service.yaml:2:3): Invalid service type ExternalName. Supported values are: ClusterIP, NodePort
Error: execution error at (go-templating-deep-dive/templates/validation.yaml:5:4): Invalid value for: securityContext.runAsUser. Containers cannot be run as root users. Please provide a uid greater than 0
Error: execution error at (go-templating-deep-dive/templates/validation.yaml:2:10): securityContext.runAsUser is required when setting securityContext and enabled is true
```

The chart's check is `eq 0`, so `--set securityContext.runAsUser=-1` renders without an error.
