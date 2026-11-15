# Understanding the dot in Helm templates

## Overview

In this exercise, we'll print the dot inside and outside a `range` loop, compare it with `$`, and see why the Service passes `$` to its named templates while the Deployment passes `.`.
Here's what we'll aim to implement:

1. Print the dot inside the Service's `range` loop.
2. Print it outside the loop, and compare both with `$`.
3. Read the Service's settings through the dot instead of the loop variable.
4. Check why the Deployment can keep passing `.`.

## Step-by-step guide

Run the commands from this folder. The chart in `go-templating-deep-dive/` is the end state of this exercise.
It continues from exercise 07's chart, so to follow the steps, copy `../07-range-maps/go-templating-deep-dive` into an empty directory and edit that copy.

1. **Print the dot inside the loop:**

   The Go template syntax names the dot: "Execution of the template walks the structure and sets the cursor, represented by a period '.' and called "dot", to the value at the current location in the structure as execution proceeds."
   In `templates/service.yaml`, add a YAML comment after the `---`, so the value appears in the rendered output:

   ```yaml
   {{- range $key, $svc := (.Values.services | default dict) }}
   ---
   # The value of the .: {{ . }} - type, port
   ```

   ```bash
   helm template go-templating-deep-dive -s templates/service.yaml
   ```

   ```text
   # The value of the .: map[port:80 type:ClusterIP] - type, port
   # The value of the .: map[port:30007 type:NodePort] - type, port
   ```

   Inside `range`, "dot is set to the successive elements of the array, slice, or map": for a map, that's each value, the same as `$svc`, not the key.
   `{{ toJson . }}` prints the same value in a more readable form, `{"port":80,"type":"ClusterIP"}`.

2. **Print the dot outside the loop:**

   Copy the comment line above the `range`, and render again.
   The line outside the loop prints the top-level object, one long line that starts like this:

   ```text
   # The value of the .: map[Capabilities:0x… Chart:map[APIVersion:v2 Annotations:map[] AppVersion:0.1.0 …
   ```

   Its keys are the built-in objects, `Capabilities`, `Chart`, `Files`, `Release`, `Subcharts`, `Template`, and `Values` (see **23 - Template syntax basics**).
   `Release` holds what the named templates use: `Release:map[IsInstall:true IsUpgrade:false Name:release-name Namespace:default Revision:1 Service:Helm]`.
   The line sits before the first `---`, so it forms a document of its own, and Helm prints it after the two Services. Remove it.

3. **Compare the dot with `$`:**

   In the comment inside the loop, replace `.` with `$`:

   ```yaml
   # The value of the .: {{ $ }} - type, port
   ```

   Both Services now print the top-level object, the same as step 2.
   The Go template syntax defines `$`: "When execution begins, $ is set to the data argument passed to Execute, that is, to the starting value of dot."
   The dot moves with `range`, and `$` doesn't. Change the comment back to `.`.

   That's why the Service passes `$` to `include`: inside the loop, `.` holds only `port` and `type`, and the `fullname` named template reads `.Release.Name` and `.Chart.Name`.

   **Inside a named template, `$` is the context it received:** a named template starts its own execution, so its `$` is whatever `include` passed.
   A named template that reads `$.Release.Name`, included with `.Values`, fails with `nil pointer evaluating interface {}.Name`, just as `.Release.Name` does.

4. **Read the settings through the dot:**

   Inside the loop, the dot is the Service's settings, so `.type` and `.port` work as well as `$svc.type` and `$svc.port`. This is the file in `go-templating-deep-dive/templates/service.yaml`:

   ```yaml
   {{- range $key, $svc := (.Values.services | default dict) }}
   ---
   # The value of the .: {{ . }} - type, port
   apiVersion: v1
   kind: Service
   metadata:
     name: {{ include "go-templating-deep-dive.fullname" $ }}-{{ $key }}
     labels:
       {{- include "go-templating-deep-dive.selectorLabels" $ | nindent 4 }}
   spec:
     type: {{ .type }}
     selector:
       {{- include "go-templating-deep-dive.selectorLabels" $ | nindent 4 }}
     ports:
       - protocol: TCP
         port: {{ .port }}
         targetPort: {{ $.Values.containerPorts.http }}
   {{- end }}
   ```

   The rendered Services are the same as in exercise 07, apart from the comment.
   `.type` reads a key of the current value directly, without going through `.Values`.

   The two forms differ in nested blocks: inside another `range` or a `with`, the dot changes again, while `$svc` still holds the Service.
   In a nested `{{ range list "a" }}`, `.` is `"a"`, and `$svc.type` still renders `ClusterIP`.

   The comment line is for exploring only: it ends up in the rendered manifest, and printed at the top level, it would include every value, secrets passed as values among them.
   The chart in this folder keeps it, as upstream does; leave it out of real charts.

5. **Check why the Deployment keeps `.`:**

   `templates/deployment.yaml` passes `.` to its `include` calls, and needs no `$`.
   Its actions sit outside any `range` or `with`, so the dot is the top-level object there.
   The `if` around its `ports` doesn't change that: for `if`, the Go template syntax says "Dot is unaffected."

## Conclusion

In this exercise, we saw that the dot is the top-level object until `range` or `with` moves it to the current element, while `$` keeps the value the template started with.
Inside a loop, `$` reaches the chart's top-level objects, and `.` or the loop variable reaches the element.
