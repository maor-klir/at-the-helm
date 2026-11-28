#helm #kubernetes #templating

# The dot and `with` blocks

The dot is the value that actions such as `.Values` and `.port` read from.
It starts as the chart's top-level object, `range` and `with` move it to a nested value, and `$` keeps the value it started with.

How variables are declared and how far they reach is in **34 - Variables and scope**.

The examples come from `go-templating-deep-dive`, a chart written from scratch to try the Helm template language: a Deployment of nginx Pods, with a `securityContext` value for the Pod's user and group, and one Service per entry of the `services` map.
Its `templates/sandbox.yaml` holds template experiments and isn't a Kubernetes object, so the chart is only rendered with `helm template`.

## What the dot holds

The Go template syntax names it: *"Execution of the template walks the structure and sets the cursor, represented by a period '.' and called "dot", to the value at the current location in the structure as execution proceeds."*
Helm's guide describes it as a scope: *"Recall that `.` is a reference to _the current scope_."*

At the top of a template file, the dot is the top-level object, whose keys are the built-in objects: `Capabilities`, `Chart`, `Files`, `Release`, `Subcharts`, `Template`, and `Values` (see **23 - Template syntax basics**).
`typeOf .` returns `common.Values` there, and `.Release.Name` reads the `Name` key of its `Release` map.

**Printing the dot shows where a template is:** a YAML comment such as `# {{ . }}` renders the current value, and `# {{ toJson . }}` renders it in a more readable form, such as `{"port":80,"type":"ClusterIP"}`.
The comment ends up in the rendered manifest, and at the top level it prints every value, so it's for exploring only.

## Which actions move the dot

| Action | The dot inside it |
|---|---|
| `if` | unchanged: *"Dot is unaffected."* |
| `range` | each element of a list, or each value of a map (see **33 - Conditionals and loops**) |
| `with` | the value of its pipeline; the block is skipped when that value is empty |
| `include` | the context passed as its second argument (see **32 - Named templates**) |

Helm's guide describes what happens at the end of a block: *"The `.` is reset to its previous scope after `{{ end }}`."*

## `with`

The Go template syntax defines it: *"If the value of the pipeline is empty, no output is generated; otherwise, dot is set to the value of the pipeline and T1 is executed."*
Inside the block, nested values are read without their full path:

```yaml
    spec:
      {{- with .Values.securityContext }}
      {{- if .enabled }}
      securityContext:
        runAsUser: {{ .runAsUser }}
        fsGroup: {{ .fsGroup }}
      {{- end }}
      {{- end }}
```

**A missing value needs no extra guard:** Helm's guide says *"The `with` block only executes if `.Values.favorite` is not empty, so a separate outer `if` guard is not needed."*

A missing `enabled` key reads as empty as well, so `default dict` before the `with` and `hasKey . "enabled"` in the condition change nothing: with `securityContext` missing, `enabled` missing, or `enabled: false`, the block renders nothing either way.

`with` has the same `else` forms as `if`.
`{{ with … }} … {{ else }} … {{ end }}` renders the `else` branch when the value is empty, and *"To simplify the appearance of with-else chains, the else action of a with may include another with directly"*: `{{ with .Values.a }}…{{ else with .Values.b }}…{{ end }}`.

**Each `with` needs its own `end`:** a `with` and an `if` closed by a single `end` fail with `parse error at (go-templating-deep-dive/templates/deployment.yaml:30): unexpected EOF`.
The line number is the end of the file, not the block that's still open.

The `helm create` scaffold combines `with` and `toYaml` for whole structured values, as in `{{- with .Values.podSecurityContext }}` followed by `{{- toYaml . | nindent 8 }}` (see **31 - Functions and pipelines**).

### `fsGroup` belongs to the Pod

The example above sets the Pod's `securityContext`.
In a container's `securityContext`, `fsGroup` renders without an error, but a server-side dry run rejects the Deployment with `strict decoding error: unknown field "spec.template.spec.containers[0].securityContext.fsGroup"`.

`kubectl explain pod.spec.securityContext.fsGroup` describes the field as *"A special supplemental group that applies to all containers in a pod."*
The `helm create` scaffold keeps the two apart, with `fsGroup: 2000` under `podSecurityContext` and `runAsUser: 1000` under `securityContext`.

## `$`

The Go template syntax defines `$`: *"When execution begins, $ is set to the data argument passed to Execute, that is, to the starting value of dot."*
Helm's guide states the consequence: *"`$` is mapped to the root scope when template execution begins and it does not change during template execution."*

Inside `range` or `with`, `$` reaches the top-level objects: `$.Release.Name`, `$.Values.containerPorts.http`, or `include "go-templating-deep-dive.fullname" $`.
With `.Release.Name` instead, the render fails with `nil pointer evaluating interface {}.Name`, because the dot holds the nested value.

**Inside a named template, `$` is the context it received:** a named template starts its own execution, so its `$` is the second argument of `include`, not the chart's top-level object.
A named template that reads `$.Release.Name`, included with `.Values`, fails with `nil pointer evaluating interface {}.Name`, just as `.Release.Name` does.

## The dot or a variable

Inside a loop, the dot and the loop variable hold the same value, so `.type` and `$svc.type` render the same.
They differ in nested blocks: inside a nested `range` or `with`, the dot changes again, while `$svc` still holds the Service.

```yaml
{{- range $key, $svc := .Values.services }}
{{- range list "a" }}
# {{ . }}/{{ $svc.type }}
{{- end }}
{{- end }}
```

This renders `# a/ClusterIP` and `# a/NodePort`: the dot is `"a"`, and `$svc` is still each Service's settings.

## Verify

From `03-go-templating-deep-dive/09-with-blocks`, our `go-templating-deep-dive` chart prints the dot inside the Service's loop and sets the security context through `with`:

```bash
helm template go-templating-deep-dive -s templates/service.yaml | grep '^# The value'
helm template go-templating-deep-dive -s templates/deployment.yaml | grep -A2 'securityContext:'
```

```text
# The value of the .: map[port:80 type:ClusterIP] - type, port
# The value of the .: map[port:30007 type:NodePort] - type, port
          securityContext:
            runAsUser: 1000
            fsGroup: 2000
```

With `--set securityContext=null`, the Deployment renders no `securityContext`.
The chart still places `fsGroup` in the container's `securityContext`, which a server-side dry run rejects.
