#helm #kubernetes #templating

# Variables and scope

A variable gives a value a name inside a template, so a long pipeline can be written once and used later.
Where it can be used depends on where it's declared: a variable lives until the `end` of its block, and never crosses into another template.

The examples come from `go-templating-deep-dive`, a chart written from scratch to try the Helm template language: a Deployment of nginx Pods and a Service, whose name comes from the named template `go-templating-deep-dive.fullname` unless the value `customName` sets one.
Its `templates/sandbox.yaml` holds template experiments and isn't a Kubernetes object, so the chart is only rendered with `helm template`.

## Declaring and reassigning

The Go template syntax defines the declaration: *"A pipeline inside an action may initialize a variable to capture the result."*
Helm's variables guide describes the form: *"In Helm templates, a variable is a named reference to another object. It follows the form `$name`. Variables are assigned with a special assignment operator: `:=`."*

A declared variable can take a new value with `=`: *"Variables previously declared can also be assigned, using the syntax $variable = pipeline"*.
The difference matters inside blocks (see the scope section below).

```yaml
{{- define "go-templating-deep-dive.fullname" -}}
{{- $fullName := printf "%s-%s" .Release.Name .Chart.Name }}
{{- if .Values.customName }}
{{- $fullName = .Values.customName }}
{{- end }}
{{- $fullName | trunc 63 | trimSuffix "-" -}}
{{- end -}}
```

**A declaration outputs nothing, but its line still has a newline:** *"An action that declares a variable produces no output."*
The newline after it, and the newlines around `if`, the assignment, and `end`, are plain text (see **23 - Template syntax basics**).

Without the leading dashes, the named template's output starts with a newline, the name lands on its own line under `name:`, and the render fails with `could not find expected ':'`.
With `customName` empty, a dash on the `if` alone is enough, because the `if` body never renders; with a custom name set, the newlines inside the body render too, so every line in the block needs `{{-`.

## Variables or `default`

For a fallback value, the Sprig `default` function replaces the `if` and the reassignment:

```yaml
{{- define "go-templating-deep-dive.fullname" -}}
{{- $defaultName := printf "%s-%s" .Release.Name .Chart.Name }}
{{- .Values.customName | default $defaultName | trunc 63 | trimSuffix "-" -}}
{{- end -}}
```

Helm's guide places it: *"In an actual chart, all static default values should live in the `values.yaml`, and should not be repeated using the `default` command (otherwise they would be redundant). However, the `default` command is perfect for computed values, which cannot be declared inside `values.yaml`."*

A name built from the release and the chart is such a computed value, so `customName` defaults to `''` in `values.yaml`, and the template supplies the fallback.

The variable keeps the pipeline readable.
Inlined, the same line needs parentheses: `.Values.customName | default (printf "%s-%s" .Release.Name .Chart.Name) | trunc 63 | trimSuffix "-"`.

**Commenting out an old block with `#` leaves it running:** to the template engine, `#` is plain text (see **23 - Template syntax basics**).
With the `if` block above prefixed by `# `, an empty `customName` renders `name:` empty and the full name in a YAML comment on the next line; `helm lint` only warns, and a server-side dry run rejects the object with `resource name may not be empty`.

## Scope

The Go template syntax defines how far a variable reaches: *"A variable's scope extends to the "end" action of the control structure ("if", "with", or "range") in which it is declared, or to the end of the template if there is no such control structure."*
A variable is also visible in the blocks nested inside its own.

| Declared | Usable |
|---|---|
| at the top of a template file, or of a `define` | until the end of that file or `define`, including nested blocks |
| inside an `if`, `with`, or `range` | until that block's `end` |
| in a `range` action, `range $i, $x := …` | inside the loop only (see **33 - Conditionals and loops**) |

**Using a variable outside its scope is a parse error:** Helm reports it with the file and line before rendering anything.
A variable declared in each branch of an `if` and `else`, then used after the `end`, fails with `parse error at (go-templating-deep-dive/templates/_helpers.tpl:7): undefined variable "$fullName"`.

To set a variable in a branch and use it after the block, declare it before the block and reassign it inside with `=`, as in the first example above.

**`:=` inside the block declares a second variable:** with `$fullName := …` in the `if` instead of `$fullName = …`, the render succeeds, but the inner variable is gone at the `end`.
The pipeline after the block uses the outer one, so the custom name is ignored without an error.

**An assignment to an undeclared variable fails only when it runs:** referencing an undeclared variable fails at parse time, but `$nope = 1` inside an `if` whose condition is false renders without an error.
When the condition is true, the render fails with `undefined variable: $nope`.

## Templates don't share variables

The Go template syntax keeps variables inside the template that declares them: *"A template invocation does not inherit variables from the point of its invocation."*

- A variable declared in `deployment.yaml` before an `include` is undefined inside the named template.
- A variable declared in `_helpers.tpl` outside a `define` is undefined inside it: each `define` is a template of its own.
- A named template's variable is undefined in the file that includes it: `$defaultName` used in `deployment.yaml` fails with `undefined variable "$defaultName"`.

A named template receives values only through the context passed to `include` (see **32 - Named templates**).
`$`, the one variable every template starts with, isn't shared either: it holds the value that template started with (see **35 - The dot and with blocks**).

## Verify

From `03-go-templating-deep-dive/04-variables`, our `go-templating-deep-dive` chart builds the resource name with `$defaultName` and `default`:

```bash
helm template go-templating-deep-dive -s templates/deployment.yaml | grep -m1 '  name:'
helm template go-templating-deep-dive -s templates/deployment.yaml --set customName=my-custom-release | grep -m1 '  name:'
```

```text
  name: release-name-go-templating-deep-dive
  name: my-custom-release
```
