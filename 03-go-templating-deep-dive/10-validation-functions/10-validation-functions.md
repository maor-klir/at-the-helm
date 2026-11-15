# Validating values with the `required` and `fail` functions

## Overview

In this exercise, we'll stop the render with a clear message when the values a user passes are missing or invalid, instead of producing manifests that fail later or behave in unexpected ways.
Here's what we'll aim to implement:

1. Require `runAsUser` and `fsGroup` when the security context is enabled, with `required`.
2. Keep the checks out of the rendered output, and choose where they live.
3. Reject a `runAsUser` of `0` with `fail`.
4. Format the error message for people or for tools.

## Step-by-step guide

Run the commands from this folder. The chart in `go-templating-deep-dive/` is the end state of this exercise.
It continues from exercise 09's chart, so to follow the steps, copy `../09-with-blocks/go-templating-deep-dive` into an empty directory and edit that copy.

1. **Add `required` checks:**

   The function list describes `required`: "If `.Bar` is empty or not defined (see default on how this is evaluated), the template will not render and will return the error message supplied instead."
   At the top of `templates/deployment.yaml`, require both settings when the security context is enabled:

   ```yaml
   {{- if and .Values.securityContext .Values.securityContext.enabled }}
   {{ required "securityContext.runAsUser is required when setting securityContext and enabled is true" .Values.securityContext.runAsUser }}
   {{ required "securityContext.fsGroup is required when setting securityContext and enabled is true" .Values.securityContext.fsGroup }}
   {{- end }}
   ```

   `and` stops at the first empty argument: "Evaluation proceeds through the arguments left to right and returns when the result is determined." Without `securityContext`, `.Values.securityContext.enabled` is never evaluated.

   ```bash
   helm template go-templating-deep-dive -s templates/deployment.yaml
   ```

   The render fails with `mapping values are not allowed in this context`.
   `--debug` shows why: `required` returns the value it checks, so `1000` and `2000` are printed above `apiVersion: apps/v1`.

2. **Discard the result with a variable:**

   Assign each result to a variable that's never used, since "An action that declares a variable produces no output." (see exercise 04):

   ```yaml
   {{- if and .Values.securityContext .Values.securityContext.enabled }}
   {{- $_ := required "securityContext.runAsUser is required when setting securityContext and enabled is true" .Values.securityContext.runAsUser }}
   {{- $_ := required "securityContext.fsGroup is required when setting securityContext and enabled is true" .Values.securityContext.fsGroup }}
   {{- end }}
   ```

   The Deployment renders as before. Remove `runAsUser`, and the render stops with the message:

   ```bash
   helm template go-templating-deep-dive --set securityContext.runAsUser=null
   ```

   ```text
   Error: execution error at (go-templating-deep-dive/templates/deployment.yaml:2:10): securityContext.runAsUser is required when setting securityContext and enabled is true
   ```

   With `--set securityContext=null`, the `if` skips the checks, and the render succeeds.

   **`required` accepts more than its description suggests:** in Helm 4.3, it stops the render only for a missing or `null` value and for an empty string.
   `0`, `false`, `[]`, and `{}` pass, although they count as empty for `default`. So `runAsUser: 0` passes `required`, and step 6 catches it with `fail`.

   **`helm lint` doesn't report a missing required value:** `helm lint go-templating-deep-dive --set securityContext.runAsUser=null` ends with `1 chart(s) linted, 0 chart(s) failed`. Render with `helm template` to see the check.

3. **Put `required` where the value is used:**

   A check can also sit on the line that uses the value. Remove the block from step 2, and in the `with` block, replace `.runAsUser` and `.fsGroup`:

   ```yaml
   runAsUser: {{ required "securityContext.runAsUser is required when setting securityContext and enabled is true" .runAsUser }}
   fsGroup: {{ required "securityContext.fsGroup is required when setting securityContext and enabled is true" .fsGroup }}
   ```

   With `runAsUser` removed, the error now points at the line in the `with` block, `deployment.yaml:23:26`.
   Inline checks sit next to the value; checks in one place are easier to review, but each result needs a variable. Revert to the checks from step 2.

4. **Check why `_helpers.tpl` doesn't work:**

   Move the four lines from step 2 to the top of `templates/_helpers.tpl`, and render with `runAsUser` removed.
   The render succeeds with an empty `runAsUser:`, and no check runs.

   Helm's named templates guide explains: "files whose name begins with an underscore (`_`) are assumed to _not_ have a manifest inside. These files are not rendered to Kubernetes object definitions, but are available everywhere within other chart templates for use."
   Only the named templates in such a file are used; text outside a `define` never runs.

5. **Move the checks to `validation.yaml`:**

   Move the lines to a new file, `templates/validation.yaml`.
   With `runAsUser` removed, the render fails again, now at `validation.yaml:2:10`.

   With valid values, the file renders nothing, so it adds no document to the output; `helm template go-templating-deep-dive -s templates/validation.yaml` reports `could not find template templates/validation.yaml in chart`.

6. **Reject `0` with `fail`:**

   The function list describes `fail`: "Unconditionally returns an empty `string` and an `error` with the specified text. This is useful in scenarios where other conditionals have determined that template rendering should fail."
   A `{{- fail "I will always fail" }}` stops every render with `execution error at (…): I will always fail`, so `fail` goes inside an `if`.

   A `runAsUser` of `0` runs the container as root. Inside the outer `if`, add:

   ```yaml
   {{- if eq .Values.securityContext.runAsUser 0 }}
   {{- fail "Containers cannot be run as root users. Please provide a UID greater than 0" }}
   {{- end }}
   ```

   The render fails with `error calling eq: incompatible types for comparison: float64 and int`.
   A number from `values.yaml` is a `float64`, and `0` is an `int` (see **33 - Conditionals and loops**). Convert it with `int` first.

   Piped, the converted value becomes the last argument, `eq 0 <runAsUser>`, and the message names the value's path. This is the file in `go-templating-deep-dive/templates/validation.yaml`:

   ```yaml
   {{- if and .Values.securityContext .Values.securityContext.enabled -}}
   {{- $_ := required "securityContext.runAsUser is required when setting securityContext and enabled is true" .Values.securityContext.runAsUser -}}
   {{- $_ := required "securityContext.fsGroup is required when setting securityContext and enabled is true" .Values.securityContext.fsGroup -}}
   {{- if int .Values.securityContext.runAsUser | eq 0 -}}
   {{- fail "Invalid value for: securityContext.runAsUser. Containers cannot be run as root users. Please provide a uid greater than 0" -}}
   {{- end -}}
   {{- end -}}
   ```

   With `--set securityContext.runAsUser=0`, the render fails with that message; with `1000`, it succeeds.

   **The check covers only `0`:** `--set securityContext.runAsUser=-1` passes, although the message asks for a UID greater than 0.
   `{{- if le (int .Values.securityContext.runAsUser) 0 -}}` rejects `0` and every negative value.
   `int` also turns a string that isn't a number into `0`, so `--set-string securityContext.runAsUser=abc` fails with the root message.

7. **Format the message:**

   `\n` in the message starts a new line, which makes a long message easier to read in a terminal:

   ```yaml
   {{- fail "\n\nInvalid value for: securityContext.runAsUser\n\nContainers cannot be run as root users. Please provide a uid greater than 0\n" -}}
   ```

   For tools that parse the output, build the message as JSON. `fail` takes one argument, so the pipeline goes in parentheses:

   ```yaml
   {{- fail (dict "error" "securityContext.runAsUser" "message" "Containers cannot be run as root users. Please provide a uid greater than 0" | toJson) -}}
   ```

   ```text
   Error: execution error at (go-templating-deep-dive/templates/validation.yaml:5:4): {"error":"securityContext.runAsUser","message":"Containers cannot be run as root users. Please provide a uid greater than 0"}
   ```

   Without the parentheses, `dict` and its four arguments become arguments of `fail`, and the render fails with `wrong number of args for fail: want 1 got 5`.
   Revert to the plain message from step 6.

## Conclusion

In this exercise, we used `required` to stop the render when a value is missing and `fail` to stop it when a value is invalid, with the checks in a template that renders nothing.
`required` misses `0` and `false`, and `helm lint` doesn't report it, so test each check with `helm template` and values that should fail.
