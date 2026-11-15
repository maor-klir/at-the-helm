# Iterating over lists with `range` in Helm templates

## Overview

In this exercise, we'll replace the single Service setting with a list of Services, and render one Service object per list item with `range`.
Here's what we'll aim to implement:

1. Turn the `service` settings in `values.yaml` into a `services` list.
2. Render the container port only when the list has items.
3. Loop over the list with `range`, and reach the chart's top-level values with `$`.
4. Separate the rendered Services into YAML documents, and give each one a unique name.

## Step-by-step guide

Run the commands from this folder. The chart in `go-templating-deep-dive/` is the end state of this exercise.
It continues from exercise 04's chart, which exercise 05 left unchanged, so to follow the steps, copy `../04-variables/go-templating-deep-dive` into an empty directory and edit that copy.

1. **Turn the Service settings into a list:**

   In `values.yaml`, replace the `service` block with a `services` list, starting with one item:

   ```yaml
   ## Settings for nginx Services
   ##
   ## @param services[*].type The type of Service in front of the nginx Pods
   ## @param services[*].port The port where the Service is receiving requests
   services:
     - type: ClusterIP
       port: 80
   ```

   Renaming `service` to `services` changes the chart's interface: values files written for the old one stop working, so a real chart would release this as a new major version.
   Both templates still read `.Values.service`, and the render fails with `nil pointer evaluating interface {}.enabled`.

2. **Render the container port only when there are Services:**

   The Service template is rewritten in step 3; until then, empty `templates/service.yaml` so the Deployment can render on its own.
   In `templates/deployment.yaml`, render the container's `ports` only when the list has items:

   ```yaml
   {{- if len .Values.services }}
   ```

   `len` "Returns the integer length of its argument.", and `0` counts as false, so the condition needs no comparison.
   Render with the list removed:

   ```bash
   helm template go-templating-deep-dive --set services=null
   ```

   The render fails with `error calling len: len of nil pointer`: a missing value has no length.
   Give `len` an empty list instead:

   ```yaml
   {{- if .Values.services | default list | len }}
   ```

   `list` with no arguments returns an empty list, which `default` uses when `.Values.services` is empty or missing.
   With `--set services=null` or `--set-json 'services=[]'`, the render succeeds and the container has no `ports`.

   A plain `{{- if .Values.services }}` gives the same three results without `len` and `default`: the Go template syntax counts "any array, slice, map, or string of length zero" and a nil value as empty, so as false.
   The `default list` is there only because `len` fails on a missing value.

3. **Loop over the Services with `range`:**

   Restore the content of `templates/service.yaml`, and replace its `if` with a `range` over the list.
   Use the loop's variables instead of `.Values.service`, and start the `end` with `{{-`:

   ```yaml
   {{- range $idx, $svc := (.Values.services | default list) }}
   apiVersion: v1
   kind: Service
   metadata:
     name: {{ include "go-templating-deep-dive.fullname" . }}
     labels:
       {{- include "go-templating-deep-dive.selectorLabels" . | nindent 4 }}
   spec:
     type: {{ $svc.type }}
     selector:
       {{- include "go-templating-deep-dive.selectorLabels" . | nindent 4 }}
     ports:
       - protocol: TCP
         port: {{ $svc.port }}
         targetPort: {{ .Values.containerPorts.http }}
   {{- end }}
   ```

   Helm's guide describes the order: "Note that `range` comes first, then the variables, then the assignment operator, then the list."
   For a list, the first variable gets the index, starting from zero, and the second gets the element.
   A `range` over a missing value outputs nothing without an error, so the `default list` here is a safeguard, not a requirement.

   Render, and it fails inside the `fullname` named template:

   ```text
   go-templating-deep-dive/templates/_helpers.tpl:2:43
     executing "go-templating-deep-dive.fullname" at <.Release.Name>:
       nil pointer evaluating interface {}.Name
   ```

   `range` changes the dot: "dot is set to the successive elements of the array, slice, or map".
   Inside the loop, the dot is the current Service, `{type: ClusterIP, port: 80}`, so the `include` passes the Service instead of the chart's top-level object, and `.Release.Name` doesn't exist in it.

   `$` still points to the top-level object; Helm's guide calls it "one variable that will always point to the root context".
   Pass `$` to the three `include` calls, and render again. The next error is `nil pointer evaluating interface {}.containerPorts`, at `.Values.containerPorts.http`, for the same reason.
   Change it to `$.Values.containerPorts.http`, and the Service renders. Exercise 08 covers the dot in depth.

4. **Add a second Service:**

   Add a NodePort Service to the list. This is the block in `go-templating-deep-dive/values.yaml`:

   ```yaml
   ## Settings for nginx Services
   ##
   ## @param services[*].type The type of Service in front of the nginx Pods
   ## @param services[*].port The port where the Service is receiving requests
   services:
     - type: ClusterIP
       port: 80
     - type: NodePort
       port: 30007
   ```

   `port: 30007` is the Service's own port, not the node port.
   The Kubernetes documentation describes how the node port is chosen: "the Kubernetes control plane allocates a port from a range specified by `--service-node-port-range` flag (default: 30000-32767)", unless the `nodePort` field sets one.
   Its NodePort example uses `port: 80` with `nodePort: 30007`. Node ports on our cluster aren't reachable from the laptop anyway, so `kubectl port-forward` is how we reach either Service.

   ```bash
   helm template go-templating-deep-dive -s templates/service.yaml
   ```

   Both Services render, one after the other, with no `---` between them, so they form a single YAML document whose keys repeat.
   `helm template` and `helm lint` report nothing, but a server-side dry run shows the result:

   ```bash
   helm template go-templating-deep-dive -s templates/service.yaml | kubectl -n default apply --dry-run=server -f -
   ```

   ```text
   service/release-name-go-templating-deep-dive created (server dry run)
   ```

   Only one Service is created: the second Service's keys overwrite the first's, so only the NodePort Service is left.

5. **Separate the documents with `---`:**

   Add `---` as the first line inside the loop:

   ```yaml
   {{- range $idx, $svc := (.Values.services | default list) }}
   ---
   ```

   `---` is plain YAML, not template syntax. Helm's guide on YAML describes it: "It is possible to place more than one YAML document into a single file. This is done by prefixing a new document with `---`".
   The same guide adds: "We recommend only using multiple documents per file when it is absolutely necessary. Having multiple documents in a file can be difficult to debug."

   Render again: each Service is now its own document, but both are named `release-name-go-templating-deep-dive`.
   A namespace holds one Service per name, so only one of them could exist.

6. **Make the names unique with the index:**

   Append the index to the name. This is the file in `go-templating-deep-dive/templates/service.yaml`:

   ```yaml
   {{- range $idx, $svc := (.Values.services | default list) }}
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: {{ include "go-templating-deep-dive.fullname" $ }}-{{ $idx }}
     labels:
       {{- include "go-templating-deep-dive.selectorLabels" $ | nindent 4 }}
   spec:
     type: {{ $svc.type }}
     selector:
       {{- include "go-templating-deep-dive.selectorLabels" $ | nindent 4 }}
     ports:
       - protocol: TCP
         port: {{ $svc.port }}
         targetPort: {{ $.Values.containerPorts.http }}
   {{- end }}
   ```

   The Services are now named `release-name-go-templating-deep-dive-0` and `release-name-go-templating-deep-dive-1`.

   **The suffix comes after the 63-character cut:** `fullname` truncates the name to 63 characters, and `-0` is added after it.
   With a 48-character release name, the names are 64 characters long, and a server-side dry run rejects them with `must be no more than 63 characters`.

   **The names follow the order of the list:** reorder the items, and `-0` becomes the NodePort Service.
   Removing the first item renames the second one: an upgrade would turn `-0` into the NodePort Service and delete `-1`.
   Exercise 07 replaces the index with a name, by turning the list into a map.

## Conclusion

In this exercise, we rendered one Service per list item with `range`, used `$` to reach the chart's top-level object inside the loop, and separated the rendered objects with `---`.
Names built from the index are unique, but they depend on the order of the list.
