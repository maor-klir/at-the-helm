# Using `with` blocks in Helm templates

## Overview

In this exercise, we'll add a security context to the nginx container and use `with` to shorten the references to its values.
Here's what we'll aim to implement:

1. Add `securityContext` settings to `values.yaml`, and render them with `if`.
2. Move the dot to the settings with `with`, and read them with short references.
3. Guard against missing settings, and check where `fsGroup` belongs.
4. Reach the top-level objects with `$` inside `with`, and see how far a variable declared there reaches.

## Step-by-step guide

Run the commands from this folder. The chart in `go-templating-deep-dive/` is the end state of this exercise.
It continues from exercise 08's chart, so to follow the steps, copy `../08-understanding-the-dot/go-templating-deep-dive` into an empty directory and edit that copy.

1. **Add the security context values:**

   In `values.yaml`, add the settings after `image`:

   ```yaml
   ## Settings for nginx container securityContext
   ##
   ## @param securityContext.enabled
   ## @param securityContext.runAsUser
   ## @param securityContext.fsGroup
   securityContext:
     enabled: true
     runAsUser: 1000
     fsGroup: 2000
   ```

2. **Render the settings with `if`:**

   In `templates/deployment.yaml`, add the block after the container's `image`:

   ```yaml
   {{- if .Values.securityContext.enabled }}
   securityContext:
     runAsUser: {{ .Values.securityContext.runAsUser }}
     fsGroup: {{ .Values.securityContext.fsGroup }}
   {{- end }}
   ```

   ```bash
   helm template go-templating-deep-dive -s templates/deployment.yaml
   ```

   The container gets the `securityContext`, and with `--set securityContext.enabled=false`, it's gone.
   Every reference repeats `.Values.securityContext`, and the paths grow with every level the settings are nested under.

3. **Move the dot with `with`:**

   The Go template syntax defines the block: "If the value of the pipeline is empty, no output is generated; otherwise, dot is set to the value of the pipeline and T1 is executed."
   Replace the block with a `with` that prints the dot in a YAML comment:

   ```yaml
   {{- with .Values.securityContext }}
   # The value of the .: {{ . }}
   {{- end }}
   ```

   The comment renders as `# The value of the .: map[enabled:true fsGroup:2000 runAsUser:1000]`.
   Inside the block, the dot is the `securityContext` map, and Helm's guide adds: "The `.` is reset to its previous scope after `{{ end }}`."

4. **Shorten the references:**

   Replace the comment with the `if` and the settings, now read through the dot:

   ```yaml
   {{- with .Values.securityContext }}
   {{- if .enabled }}
   securityContext:
     runAsUser: {{ .runAsUser }}
     fsGroup: {{ .fsGroup }}
   {{- end }}
   ```

   The render fails: `parse error at (go-templating-deep-dive/templates/deployment.yaml:30): unexpected EOF`.
   The `with` and the `if` each need an `end`, and this block has one. The line number points at the end of the file, not at the block that's still open, so count the opening and closing actions.
   Add the second `{{- end }}`, and the render succeeds.

5. **Guard against missing settings:**

   Default to an empty map, and render the block only if `enabled` exists and is true. This is the file in `go-templating-deep-dive/templates/deployment.yaml`:

   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: {{ include "go-templating-deep-dive.fullname" . }}
     labels: 
       {{- include "go-templating-deep-dive.selectorLabels" . | nindent 4 }}
   spec:
     replicas: {{ .Values.replicaCount }}
     selector:
       matchLabels: 
         {{- include "go-templating-deep-dive.selectorLabels" . | nindent 6 }}
     template:
       metadata:
         labels: 
           {{- include "go-templating-deep-dive.selectorLabels" . | nindent 8 }}
       spec:
         containers:
           - name: nginx
             image: "{{ .Values.image.name }}:{{ .Values.image.tag }}"
             {{- with .Values.securityContext | default dict }}
             {{- if and (hasKey . "enabled") .enabled }}
             securityContext:
               runAsUser: {{ .runAsUser }}
               fsGroup: {{ .fsGroup }}
             {{- end }}
             {{- end }}
             {{- if .Values.services | default dict | len }}
             ports:
               - containerPort: {{ .Values.containerPorts.http }}
             {{- end }}
   ```

   The function list describes `hasKey`: "The `hasKey` function returns `true` if the given dict contains the given key.", with the map first and the key second.
   With `--set securityContext.enabled=false`, `--set securityContext.enabled=null`, or `--set securityContext=null`, the container has no `securityContext`.

   The plain `{{- with .Values.securityContext }}` and `{{- if .enabled }}` from step 4 give the same four results.
   Helm's guide says so for `with`: "The `with` block only executes if `.Values.favorite` is not empty, so a separate outer `if` guard is not needed."
   A missing `enabled` key reads as empty, so `if .enabled` is already false without `hasKey`.

6. **Check where `fsGroup` belongs:**

   The render succeeds, but the API server rejects the Deployment:

   ```bash
   helm template go-templating-deep-dive -s templates/deployment.yaml | kubectl -n default apply --dry-run=server -f -
   ```

   ```text
   strict decoding error: unknown field "spec.template.spec.containers[0].securityContext.fsGroup"
   ```

   `fsGroup` exists only in the Pod's `securityContext`; `kubectl explain pod.spec.securityContext.fsGroup` describes it as "A special supplemental group that applies to all containers in a pod."
   The Kubernetes documentation on security contexts adds about the container-level one: "Container settings do not affect the Pod's Volumes."
   The `helm create` scaffold keeps the two apart, with `fsGroup: 2000` under `podSecurityContext` and `runAsUser: 1000` under `securityContext`.

   Moving the block from the container to the Pod's `spec`, both fields valid there, passes the server-side dry run:

   ```yaml
       spec:
         {{- with .Values.securityContext }}
         {{- if .enabled }}
         securityContext:
           runAsUser: {{ .runAsUser }}
           fsGroup: {{ .fsGroup }}
         {{- end }}
         {{- end }}
         containers:
   ```

   The chart in this folder keeps the container placement, as the course's chart does.

7. **Reach the top level with `$`:**

   Inside the `with`, add a comment that reads the release name:

   ```yaml
   # release: {{ $.Release.Name }}
   ```

   It renders `# release: release-name`.
   With `.Release.Name` instead, the render fails with `nil pointer evaluating interface {}.Name`, because the dot is the `securityContext` map.
   Helm's guide explains `$`: "`$` is mapped to the root scope when template execution begins and it does not change during template execution."

8. **Declare a variable inside `with`:**

   Declare a variable as the first line inside the `with`, and use it after the block's last `end`:

   ```yaml
   {{- $myvar := $.Release.Name }}
   ```

   ```yaml
   # trying to access myvar: {{ $myvar }}
   ```

   The render fails with `parse error at (go-templating-deep-dive/templates/deployment.yaml:28): undefined variable "$myvar"`: like `if` and `range`, `with` ends a variable's scope at its `end`.
   Declared before the `with`, the variable works inside it, and the comment renders `# trying to access myvar: release-name` (see exercise 05).
   Remove the comments and the variable when you're done.

## Conclusion

In this exercise, we used `with` to set the dot to the security context settings, which shortened every reference to them and skipped the block when the settings are missing.
Inside `with`, `$` reaches the top-level objects, and a variable declared inside the block ends at its `end`.
