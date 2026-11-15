# Iterating over maps with `range` in Helm templates

## Overview

In this exercise, we'll turn the `services` list into a map, so each Service is identified by its key instead of its position.
Here's what we'll aim to implement:

1. Turn the `services` list in `values.yaml` into a map.
2. Update the defaults and the loop variable in the templates.
3. Check that the rendered Services no longer depend on the order of the values.
4. Override a single Service, and compare that with overriding a list item.
5. Choose keys that are valid in object names.

## Step-by-step guide

Run the commands from this folder. The chart in `go-templating-deep-dive/` is the end state of this exercise.
It continues from exercise 06's chart, so to follow the steps, copy `../06-range-lists/go-templating-deep-dive` into an empty directory and edit that copy.

1. **Turn the list into a map:**

   In exercise 06, each Service's name came from its position in the list, so reordering or removing an item renamed other Services.
   Services are quick to delete and create again, but a renamed StatefulSet gets new PersistentVolumeClaims and starts with empty volumes.
   Each claim's name includes the StatefulSet's name, as in the Kubernetes tutorial's `www-web-0`, for the claim template `www` in the StatefulSet `web`; the old claims and their data are kept by default, but no Pod uses them.

   In `values.yaml`, give each Service a key instead. This is the block in `go-templating-deep-dive/values.yaml`:

   ```yaml
   ## Settings for nginx Services
   ## services is a map with the following schema
   ##
   ## @param services["*"].type The type of Service in front of the nginx Pods
   ## @param services["*"].port The port where the Service is receiving requests
   services:
     svc1:
       type: ClusterIP
       port: 80
     svc2:
       type: NodePort
       port: 30007
   ```

   In the comments, `"*"` stands for any key, as `[*]` stood for any list item.

   ```bash
   helm template go-templating-deep-dive -s templates/service.yaml
   ```

   The Services are already named `release-name-go-templating-deep-dive-svc1` and `release-name-go-templating-deep-dive-svc2`, because `range` gives a map's key as its first variable.
   The Go template syntax defines both cases: "$index and $element are set to the successive values of the array/slice index or map key and element, respectively."

2. **Update the defaults and the loop variable:**

   The templates work, but they still read as if they iterated over a list.
   In `templates/deployment.yaml`, default to an empty map:

   ```yaml
   {{- if .Values.services | default dict | len }}
   ```

   In `templates/service.yaml`, default to an empty map and rename `$idx` to `$key`. This is the file in `go-templating-deep-dive/templates/service.yaml`:

   ```yaml
   {{- range $key, $svc := (.Values.services | default dict) }}
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: {{ include "go-templating-deep-dive.fullname" $ }}-{{ $key }}
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

   The output is the same; the template now says what it iterates over.

3. **Reorder and remove Services:**

   In `values.yaml`, move `svc2` above `svc1`, and render again.
   The output doesn't change: `svc1` still renders first, and it's still the ClusterIP Service.
   The Go template syntax gives the order: "If the value is a map and the keys are of basic type with a defined order, the elements will be visited in sorted key order."

   The order of the output isn't what matters, though; each name staying with its own settings is.
   Remove `svc1`, and `svc2` keeps its name:

   ```bash
   helm template go-templating-deep-dive -s templates/service.yaml --set services.svc1=null
   ```

   An upgrade with these values would delete only `release-name-go-templating-deep-dive-svc1` and leave the other Service as it is. Move `svc2` back below `svc1` when you're done.

4. **Override a single Service:**

   Helm's best practices recommend maps with overrides in mind: "it's often better to structure your values file using maps."
   Setting a list item, as in `--set servers[0].port=80`, "is prone to errors if at some later time the order of the `servers` is changed."

   ```bash
   helm template go-templating-deep-dive -s templates/service.yaml --set services.svc2.port=8080
   ```

   Only `svc2`'s port changes, because Helm merges maps key by key. A values file with only `svc2`'s `port` does the same.

   A list isn't merged: an override replaces it whole. Try the same with exercise 06's chart:

   ```bash
   helm template ../06-range-lists/go-templating-deep-dive -s templates/service.yaml --set 'services[1].port=8080'
   ```

   The list becomes one with an empty first item and `port: 8080` as its second, and the render fails with `nil pointer evaluating interface {}.type`.
   A values file that lists only the NodePort Service leaves only that one, and the ClusterIP Service is gone.

   **Merging also affects removal:** `--set-json 'services={}'` removes nothing, because an empty map merges into the defaults without changing them.
   `--set services=null` removes the key, and with it every Service and the container's `ports`.

5. **Choose keys that work in names:**

   The key becomes part of each Service's name, so it has to follow the naming rules.
   A key such as `Svc_3` renders, but a server-side dry run rejects the Service: "a DNS-1035 label must consist of lower case alphanumeric characters or '-', start with an alphabetic character".
   Keep keys short, lowercase, and made of letters, digits, and dashes; the 63-character limit from exercise 06 applies to the whole name, key included.

## Conclusion

In this exercise, we replaced the list with a map, so each Service's name comes from its key and no longer depends on the order of the values.
Maps also suit overrides: Helm merges them key by key, while a list is always replaced whole.
