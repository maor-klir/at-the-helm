#helm #kubernetes #templating

# Conditionals and loops

Two actions decide what a template renders: `if` renders a block or skips it, and `range` renders a block once for each element of a list or map.
Both close with `end`, and both can have an `else`.

Which values count as false, and how an `if` around a whole template makes an object optional, are in **24 - Values and release information in a chart**.

## `if` and `else`

Besides a whole object, an `if` can wrap a few lines of one:

```yaml
containers:
  - name: nginx
    image: "{{ .Values.image.name }}:{{ .Values.image.tag }}"
    {{- if .Values.services }}
    ports:
      - containerPort: {{ .Values.containerPorts.http }}
    {{- end }}
```

An empty list or map counts as false, so `if .Values.services` needs no `len`.
The Go template syntax defines the empty values: *"The empty values are false, 0, any nil pointer or interface value, and any array, slice, map, or string of length zero."*

**More than two cases chain with `else if`:** the Go template syntax describes it as a shorthand: *"To simplify the appearance of if-else chains, the else action of an if may include another if directly"*.
The chain closes with a single `end`:

```yaml
replicas: {{ if eq .Values.environment "production" }}5{{ else if eq .Values.environment "staging" }}3{{ else }}2{{ end }}
```

### Conditions

A condition is any pipeline, most often a comparison function such as `eq`, `ne`, `lt`, or `gt` (see **31 - Functions and pipelines**).
`eq` with a missing value returns false without an error, so with no `environment` set, the chain above renders `replicas: 2`.

**Numbers from `values.yaml` are floats:** Helm's appendix on data types says *"variables in templates are _typed_"*, and `kindOf .Values.replicaCount` returns `float64` for a number from `values.yaml`.
`eq .Values.replicaCount 3` compares it with an integer and fails with `incompatible types for comparison: float64 and int`.

The same number passed with `--set replicaCount=3` is an `int64`, and the comparison works.
Converting first works for both sources: `eq (int .Values.replicaCount) 3`.

### Inline values and whitespace

An `if` and `else` on one line choose a single value.
The spaces inside the branches are plain text, so dashes on the inner side of the actions trim them (see **23 - Template syntax basics**):

```yaml
replicas: {{ if eq .Values.environment "production" -}} 5 {{- else -}} 2 {{- end }}
```

For a choice between two values, the Sprig `ternary` function is shorter: *"The `ternary` function takes two values, and a test value. If the test value is true, the first value will be returned. If the test value is empty, the second value will be returned."*
`replicas: {{ ternary 5 2 (eq .Values.environment "production") }}` renders the same as the line above.

## `range`

The Go template syntax defines the loop: *"If the value of the pipeline has length zero, nothing is output; otherwise, dot is set to the successive elements of the array, slice, or map and T1 is executed."*
In a chart, `range` typically renders one object, or one block of an object, per element of a list or map from `values.yaml`.

### Loop variables

Helm's variables guide gives the order: *"Note that `range` comes first, then the variables, then the assignment operator, then the list."*
With two variables, *"$index and $element are set to the successive values of the array/slice index or map key and element, respectively."*

| Form | Over a list | Over a map |
|---|---|---|
| `range $i, $x := …` | `$i` is the index, from 0; `$x` the element | `$i` is the key; `$x` the value |
| `range $x := …` | `$x` is the element | `$x` is the value |
| `range …` | the dot is the element | the dot is the value |

**Maps are visited in sorted key order:** *"If the value is a map and the keys are of basic type with a defined order, the elements will be visited in sorted key order."*
The order of the keys in `values.yaml` doesn't matter, and keys sort as strings: `svc1`, `svc10`, `svc2`.

### Empty and missing values

A `range` over an empty list or map renders nothing, and so does a `range` over a missing value, without an error.
An `else` renders instead: *"If the value of the pipeline has length zero, dot is unaffected and T0 is executed"*.

`len` doesn't accept a missing value: `len .Values.services` fails with `error calling len: len of nil pointer`.
A default protects it: `.Values.services | default dict | len`, or `default list` for a list.

### Ending a loop early

The Go template syntax has two actions for the innermost `range`:

- `{{break}}`: *"The innermost {{range pipeline}} loop is ended early, stopping the current iteration and bypassing all remaining iterations."*
- `{{continue}}`: *"The current iteration of the innermost {{range pipeline}} loop is stopped, and the loop starts the next iteration."*

Both usually sit inside an `if`: over `list 1 2 3 4`, breaking at 3 renders `1 2`, and continuing at 2 renders `1 3 4`.

`range` also accepts an integer: `{{ range 3 }}{{ . }} {{ end }}` renders `0 1 2`.

### The dot and `$` inside the loop

Inside `range`, the dot is the current element, so `.Values` and `.Release` can't be reached through it.
Passing `.` to `include` gives the named template the element: `include "go-templating-deep-dive.fullname" .` fails in the helper at `<.Release.Name>` with `nil pointer evaluating interface {}.Name`.

`$` keeps the top-level object: Helm's variables guide says *"there is one variable that will always point to the root context"*.
Inside the loop, `include "go-templating-deep-dive.fullname" $` and `$.Values.containerPorts.http` work (see **35 - The dot and with blocks**).

## Several objects from one template

A `range` that renders one object per element needs `---` inside the loop.
Helm's guide on YAML describes it: *"It is possible to place more than one YAML document into a single file. This is done by prefixing a new document with `---`"*.

**Without `---`, the objects merge into one:** two Services render as a single YAML document whose keys repeat.
`helm template` and `helm lint` report nothing, and a server-side dry run creates one Service, with the keys of the later one.

The same guide warns about the pattern: *"We recommend only using multiple documents per file when it is absolutely necessary. Having multiple documents in a file can be difficult to debug."*
A loop over objects is a case where it's necessary.

```yaml
{{- range $key, $svc := (.Values.services | default dict) }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ include "go-templating-deep-dive.fullname" $ }}-{{ $key }}
```

### Unique names

Objects of one kind share the names of a namespace, so each object needs a suffix that's unique within the loop:

| Suffix | Names | When an element is reordered or removed |
|---|---|---|
| `-{{ $idx }}` | `…-0`, `…-1` | other objects get new names, so `-0` can turn into a different Service |
| `-{{ $key }}` | `…-svc1`, `…-svc2` | only the removed key's object is deleted |

**The suffix comes after the 63-character cut:** `fullname` truncates the name first, so with a 48-character release name, `…-0` has 64 characters, and the API server rejects it with `must be no more than 63 characters`.

A key becomes part of a name, so it must follow the naming rules: the key `Svc_3` fails with `a DNS-1035 label must consist of lower case alphanumeric characters or '-', start with an alphabetic character`.

## Lists or maps in values

Helm's best practices weigh the two with overrides in mind: *"Since `--set` is more limited in expressiveness, the first guidelines for writing your `values.yaml` file is _make it easy to override from `--set`_."*
They conclude: *"For this reason, it's often better to structure your values file using maps."*

**Helm merges maps and replaces lists:** `--set services.svc2.port=8080` changes one entry of the `services` map and keeps the others.
On a list, `--set 'services[1].port=8080'` builds a new list whose first item is empty, and the render fails with `nil pointer evaluating interface {}.type`; a values file replaces a list whole in the same way.

**An empty map doesn't clear a map:** `--set-json 'services={}'` merges into the defaults and changes nothing.
`--set services=null` removes the key, and with it every Service (see **13 - Overriding chart values**).

## Verify

From `03-go-templating-deep-dive/07-range-maps`, our `go-templating-deep-dive` chart renders one Service per key of `services`:

```bash
helm template go-templating-deep-dive -s templates/service.yaml | grep -E '^  name:|^  type:'
```

```text
  name: release-name-go-templating-deep-dive-svc1
  type: ClusterIP
  name: release-name-go-templating-deep-dive-svc2
  type: NodePort
```

With `--set services.svc2.port=8080`, only `svc2`'s port changes, and with `--set services.svc1=null`, `svc2` keeps its name.
