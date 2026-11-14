#helm #kubernetes #templating

# Template syntax basics

Every file in a chart's `templates/` directory is rendered with the Helm template language before Helm sends anything to the cluster (see **22 - Helm chart structure**).
Its syntax comes from Go's `text/template` package, and Helm adds functions and the objects a template can read (see **02 - Benefits and limitations of Helm**).

This note covers what every template uses: actions, the dot and the built-in objects, comments, and whitespace control.

## Actions and plain text

The Go template syntax separates two kinds of text:

> *"The input text for a template is UTF-8-encoded text in any format. "Actions"--data evaluations or control structures--are delimited by "{{" and "}}"; all text outside actions is copied to the output unchanged."*

A template is plain YAML with actions in it, and a manifest with no actions at all is a valid template.
With `test: I am a string` in `values.yaml`, the template line `test: {{ .Values.test }}` renders as `test: I am a string`.

## The dot and the built-in objects

The leading dot in `.Values.test` is the cursor of the Go template syntax:

> *"Execution of the template walks the structure and sets the cursor, represented by a period '.' and called "dot", to the value at the current location in the structure as execution proceeds."*

At the top level of a template, the dot is the object Helm passes to every template.
Its fields are the built-in objects: `.Values`, `.Release`, `.Chart`, `.Files`, `.Capabilities`, `.Template`, and `.Subcharts`.
Helm's built-in objects guide notes their spelling: *"The built-in values always begin with a capital letter. This is in keeping with Go's naming convention."*

**`.Chart` follows the same rule:** it holds the fields of `Chart.yaml` under capitalized names, so `appVersion` is `.Chart.AppVersion`.
`.Template.Name` is the path of the template being rendered, such as `intro-go-templating/templates/sandbox.yaml`.

`with` and `range` blocks set the dot to another value inside them; `if` leaves it unchanged.

### What `helm template` fills in

`helm template` renders without a release and without a cluster: *"Any values that would normally be looked up or retrieved in-cluster will be faked locally."*
The release and cluster fields get placeholders:

| Field | Rendered by `helm template` | Set with |
|---|---|---|
| `.Release.Name` | `release-name` | the first argument, as in `helm template my-app ./chart` |
| `.Release.Namespace` | `default`, as our kubeconfig context sets no namespace | `-n` |
| `.Release.IsInstall`, `.Release.Revision` | `true`, `1` | — |
| `.Capabilities.KubeVersion` | `v1.37.0`, the Kubernetes version Helm 4.3.2 is built against | `--kube-version` |

Our cluster runs Kubernetes 1.35, so a template that checks `.Capabilities.KubeVersion` renders differently under `helm template` than under `helm install`, unless `--kube-version 1.35.5` is given.

## Comments

Helm's best practices name both kinds: *"Both YAML and Helm Templates have comment markers."*
A YAML comment, `# …`, is plain text and appears in the rendered output.
A Go comment, `{{/* … */}}`, is an action that's discarded.

The best practices give each a purpose.
Go comments document the template itself, and *"Inside of templates, YAML comments may be used when it is useful for Helm users to (possibly) see the comments during debugging."*

**A YAML comment doesn't stop the actions on its line:** they still run, because to the template engine the `#` is plain text.
A `{{ .Values.test }}` inside a YAML comment is filled in, and a failing function fails the render:

```text
Error: execution error at (c/templates/a.yaml:1:13): maxMem must be set
```

That error comes from `# memory: {{ required "maxMem must be set" .Values.maxMem }}`; wrapped in a Go comment instead, the line renders nothing.
The best practices warn about it: *"Beware of adding `#` YAML comments on template sections containing Helm values that may be required by certain template functions."*

**Go comments have a fixed form:** the Go template syntax describes `{{/* a comment */}}` as *"A comment; discarded. May contain newlines. Comments do not nest and must start and end at the delimiters, as shown here."*
With spaces between the braces and the comment, `{{ /* … */ }}` fails with `unexpected "/" in command`.

## Whitespace control

A Go comment outputs nothing, but its line stays: the indentation before it and the newline after it are plain text, so the comment leaves an empty line behind.
`if`, `else`, and `end` leave empty lines the same way.

The Go template syntax trims that whitespace with a dash next to the delimiter:

> *"if an action's left delimiter (by default "{{") is followed immediately by a minus sign and white space, all trailing white space is trimmed from the immediately preceding text. Similarly, if the right delimiter ("}}") is preceded by white space and a minus sign, all leading white space is trimmed from the immediately following text."*

Helm's chart template guide adds the warning that explains most surprises: *"Be careful! Newlines are whitespace!"*

### Where the dash goes

With `·` for a space and `⏎` for a newline, a comment line between `labels:⏎` and `··app:·x⏎` renders as follows:

| Source line | Rendered |
|---|---|
| `··{{/* c */}}⏎` | `labels:⏎··⏎··app:·x⏎`, an empty line |
| `··{{- /* c */}}⏎` | `labels:⏎··app:·x⏎`: the newline and indentation before the action are trimmed |
| `··{{/* c */ -}}⏎` | `labels:⏎··app:·x⏎`: the newline and indentation after it are trimmed |
| `··{{- /* c */ -}}⏎` | `labels:app:·x⏎`, invalid YAML |

The last line fails the render with `mapping values are not allowed in this context`, because both sides are trimmed and `app:` joins `labels:`.

**The space after the dash is part of the marker:** *"In these trim markers, the white space must be present: "{{- 3}}" is like "{{3}}" but trims the immediately preceding text, while "{{-3}}" parses as an action containing the number -3."*
`{{-/* … */}}` therefore fails to parse.

**Starting with `{{-` is the usual choice:** a line that outputs nothing, such as a comment or an `if`, `else`, or `end`, can start with `{{-` and leave no trace in the output.
A dash before `}}` is useful only when the following line should move up.

## Verify

The `intro-go-templating` chart has a YAML comment, Go comments with `{{-`, values, and the release and chart objects in one template:

```bash
helm template intro-go-templating
helm template my-sandbox intro-go-templating | grep 'app:'
```

The YAML comment is in the output, the Go comments and their lines are not, and the second command renders `app: my-sandbox` instead of `app: release-name`.
