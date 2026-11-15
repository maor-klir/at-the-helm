#helm #kubernetes #templating

# Functions and pipelines

Most of the work in a template is done by functions: they transform values, compare them, and build lists and dictionaries.
Pipelines chain functions together, and two functions, `toYaml` and `nindent`, turn their results into valid YAML.

The syntax around them, actions, the dot, comments, and whitespace control, is in **23 - Template syntax basics**.

## Where the functions come from

Helm's chart template guide names the sources: *"Helm has over 60 available functions. Some of them are defined by the Go template language itself. Most of the others are part of the Sprig template library."*
Helm adds its own on top, such as `include`, `tpl`, `required`, `toYaml`, and `lookup` (see **02 - Benefits and limitations of Helm**).

| Source | Examples |
|---|---|
| Go template syntax | `and`, `or`, `not`, `eq`, `ne`, `lt`, `gt`, `len`, `index`, `print`, `printf` |
| Sprig | `lower`, `replace`, `trunc`, `trimSuffix`, `default`, `list`, `dict`, `merge`, `indent`, `nindent` |
| Helm | `include`, `tpl`, `required`, `toYaml`, `lookup` |

**The Template Function List is where to look for one:** Helm's documentation lists every function on one page, *"broken down by the following categories"*.
Its 18 categories range from String, Lists, and Dictionaries to Logic and Flow Control, Type Conversion, Semantic Versions, and Cryptographic and Security.

## Calling a function

A call is the function's name followed by its arguments, separated by spaces, with no parentheses and no commas.
`lower .Values.test` returns the value in lowercase, and `replace " " "-" .Values.test` replaces each space with a dash.

**Operators are functions too:** Helm's guide says so directly: *"For templates, the operators (`eq`, `ne`, `lt`, `gt`, `and`, `or` and so on) are all implemented as functions."*
So the function comes first, in prefix notation: `and value1 value2`, not `value1 && value2`.

Some functions take a fixed number of arguments, and others take any number.
The function list describes `and` as returning *"the boolean AND of two or more arguments (the first empty argument, or the last argument)"*: `and true false` returns `false`, `and 1 "" 3` an empty string, and `and 1 2 3` returns `3`.

`eq` also takes more than two arguments.
The Go template syntax defines it: *"For simpler multi-way equality tests, eq (only) accepts two or more arguments and compares the second and subsequent to the first"*, so `eq .Values.environment "production" "prod"` is true for either value.

**`has` tests a list, `contains` a string:** the function list describes `has` as *"Test to see if a list has a particular element."* and `contains` as *"Test to see if one string is contained inside of another"*.
`has "b" (list "a" "b" "c")` returns `true`, and `contains "b" "abc"` returns `true`.

Mixing them up fails: `contains "b" (list "a" "b" "c")` stops with `wrong type for value; expected string; got []interface {}`.
Both take the list or string they search as their last argument, so a pipe can supply it: `list "a" "b" "c" | has "b"`.

**Parentheses turn a call into one argument:** `lower replace " " "-" .Values.test` passes four arguments to `lower`, and the render fails with `wrong number of args for lower: want 1 got 4`.
`lower (replace " " "-" .Values.test)` passes `lower` the result of `replace`.

## Pipelines

A pipe passes the result of one command to the next.
The Go template syntax defines where it goes: *"In a chained pipeline, the result of each command is passed as the last argument of the following command."*

`.Values.test | lower | replace " " "-"` therefore lowercases the value, then passes it to `replace` as its source string, its last argument.
Helm's guide prefers this form: *"Inverting the order is a common practice in templates. You will see `.val | quote` more often than `quote .val`. Either practice is fine."*

**The order of a pipeline can change the result:** with `test: I am a string`, `lower | replace "I" "E"` renders `i am a string`, because no capital `I` is left by the time `replace` runs.
`replace "I" "E" | lower` renders `e am a string`.

## From Go values to YAML

Without conversion, a list or a dictionary renders as Go prints it.
`list 1 2 3` renders `[1 2 3]`, and `dict "primitive" "my string" "complex" (dict "key1" "value1")` renders `map[complex:map[key1:value1] primitive:my string]`: strings, not YAML.

`toYaml` converts them: *"The `toYaml` and `toYamlPretty` functions encode an object (list, slice, array, dict, or object) into an indented YAML string."*
`toYaml` writes a dictionary's keys in alphabetical order.

**The YAML has to start on its own line:** `list: {{ list 1 2 3 | toYaml }}` renders `list: - 1` followed by the other items, and fails with `block sequence entries are not allowed in this context`; a dictionary fails the same way with `mapping values are not allowed in this context`.
`helm template --debug` prints the rendered YAML that failed to parse.

`nindent` solves it: *"The `nindent` function is the same as the indent function, but prepends a new line to the beginning of the string."*
With the new line, the action can stay on the key's line, which is why charts use `nindent` far more often than `indent`.

| Template | Result |
|---|---|
| `list: {{ list 1 2 3 }}` | `list: [1 2 3]`, a string |
| `list: {{ list 1 2 3 \| toYaml }}` | fails: `block sequence entries are not allowed in this context` |
| `list: {{ list 1 2 3 \| toYaml \| indent 2 }}` | fails the same way |
| `list: {{ list 1 2 3 \| toYaml \| nindent 2 }}` | a YAML list under `list:` |

### Structured values from `values.yaml`

The same pattern renders a structured value from `values.yaml`, such as a container's resource limits:

```yaml
resources: {{ .Values.resources | toYaml | nindent 2 }}
```

The `helm create` scaffold writes it inside a `with` block, which skips the whole block when the value is empty; inside it, the dot is the value itself:

```yaml
      {{- with .Values.podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
```

**`toJson` produces valid YAML too:** a YAML parser reads JSON, so `resources: {{ .Values.resources | toJson }}` renders `resources: {"limits":{"cpu":"100m","memory":"128Mi"}}`, which parses to the same data.
`toYaml | nindent` is the usual choice because its block style reads like the rest of the manifest.

### Matching the indentation to the depth

The indent width has to match where the value sits.
Under `list.values.example`, `nindent 2` puts the items at the level of `values`, and the render fails with `did not find expected key`; `nindent 6` puts them under `example`.

**A wrong width can also produce valid YAML with the wrong structure:** in a Deployment, `nindent 4` under `spec.selector.matchLabels` renders without an error and passes `helm lint`, but the labels become keys of `spec.selector`.
The API server rejects the object with `strict decoding error: unknown field "spec.selector.app"`, which a server-side dry run shows before installing (see **25 - The chart development workflow**).

Named templates, such as a chart's labels, are piped through `nindent` the same way, and their output is YAML already, so they need no `toYaml`.

## Verify

From `03-go-templating-deep-dive/01-functions-and-pipelines`, our `go-templating-deep-dive` chart renders a list and a dictionary through `toYaml | nindent` in `templates/sandbox.yaml`:

```bash
helm template go-templating-deep-dive -s templates/sandbox.yaml
```

```text
list:
  values:
    example:
      - 1
      - 2
      - 3

my-dict:
  complex:
    key1: value1
  primitive: my string
```
