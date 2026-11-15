# Exploring Variables in Helm Templates

## Overview

In this exercise, we'll use variables to let users set a custom name for the chart's objects, with the release and chart names as the fallback.
Here's what we'll aim to implement:

1. Add a `customName` value to `values.yaml`.
2. Store the default name in a variable, and reassign it with `if` when a custom name is set.
3. Trim the whitespace the `if` block leaves in the name.
4. Replace the `if` with the `default` function.

## Step-by-Step Guide

Run the commands from this folder. The chart in `go-templating-deep-dive/` is the end state of this exercise.
It continues from exercise 03's chart, so to follow the steps, copy `../03-if-statements/go-templating-deep-dive` into an empty directory and edit that copy.

1. **Add the `customName` Value:**

   Add the value at the top of `values.yaml`, empty by default:

   ```yaml
   ## @param customName allows to set a custom resource name for the Kubernetes resources in the chart.
   ##        Defaults to {{ .Release.Name }}-{{ .Chart.Name }}
   customName: ''
   ```

   The fallback is built from the release and chart names, so it can't be written in `values.yaml`; the template computes it when `customName` is empty.

2. **Store the Name in a Variable:**

   The Go template syntax defines a variable declaration: "A pipeline inside an action may initialize a variable to capture the result. The initialization has syntax `$variable := pipeline`".
   In `templates/_helpers.tpl`, capture the raw name in `$fullName`, and pipe the variable on instead of the expression:

   ```yaml
   {{- define "go-templating-deep-dive.fullname" -}}
   {{- $fullName := printf "%s-%s" .Release.Name .Chart.Name }}
   {{- $fullName | trunc 63 | trimSuffix "-"  -}}
   {{- end -}}
   ```

   The declaration itself outputs nothing, "An action that declares a variable produces no output.", and the newline after it is trimmed by the next line's `{{-`.

   ```bash
   helm template go-templating-deep-dive -s templates/deployment.yaml
   ```

   The name is unchanged, `release-name-go-templating-deep-dive`.

3. **Reassign the Variable with `if`:**

   Change `$fullName` when `customName` is set:

   ```yaml
   {{- define "go-templating-deep-dive.fullname" -}}
   {{- $fullName := printf "%s-%s" .Release.Name .Chart.Name }}
   {{ if .Values.customName }}
   {{ $fullName = .Values.customName }}
   {{ end }}
   {{- $fullName | trunc 63 | trimSuffix "-"  -}}
   {{- end -}}
   ```

   The reassignment uses `=`, not `:=`: "Variables previously declared can also be assigned, using the syntax `$variable = pipeline`".
   The `if` needs no comparison, because an empty string counts as false; Helm's list of false values includes "an empty string".

   Render again, and it fails:

   ```text
   Error: YAML parse error on go-templating-deep-dive/templates/deployment.yaml: error converting YAML to JSON: yaml: line 6: could not find expected ':'
   ```

   `helm template go-templating-deep-dive --debug` shows the invalid YAML, with the name on its own line:

   ```yaml
   metadata:
     name: 
   release-name-go-templating-deep-dive
   ```

   The newline before `{{ if` is plain text, so the named template's output starts with it.

4. **Trim Every Line That Outputs Nothing:**

   Start the `if`, the assignment, and the `end` with `{{-`:

   ```yaml
   {{- define "go-templating-deep-dive.fullname" -}}
   {{- $fullName := printf "%s-%s" .Release.Name .Chart.Name }}
   {{- if .Values.customName }}
   {{- $fullName = .Values.customName }}
   {{- end }}
   {{- $fullName | trunc 63 | trimSuffix "-"  -}}
   {{- end -}}
   ```

   The name is back on the `name:` line.
   With `customName` empty, the dash on the `if` alone would be enough, because the `if` body never renders.
   With a custom name set, the newlines inside the body render too, and with only `{{- if`, the render fails again with `could not find expected ':'`.
   Starting every line that outputs nothing with `{{-` covers both cases.

5. **Set a Custom Name:**

   ```bash
   helm template go-templating-deep-dive --set customName=my-custom-release --set service.enabled=true
   ```

   Both the Service and the Deployment are named `my-custom-release`.
   Setting `customName: my-custom-release` in `values.yaml` does the same; set it back to `''` afterwards.

6. **Replace the `if` with `default`:**

   Helm's guide describes the function as "`default DEFAULT_VALUE GIVEN_VALUE`. This function allows you to specify a default value inside of the template, in case the value is omitted."
   A pipe passes its input as the last argument, so piping `.Values.customName` into `default $defaultName` makes it the given value.
   Rename the variable, since it now holds only the fallback, and delete the `if` block. This is the file in `go-templating-deep-dive/templates/_helpers.tpl`:

   ```yaml
   {{- define "go-templating-deep-dive.fullname" -}}
   {{- $defaultName := printf "%s-%s" .Release.Name .Chart.Name }}
   {{- .Values.customName | default $defaultName | trunc 63 | trimSuffix "-"  -}}
   {{- end -}}

   {{- define "go-templating-deep-dive.selectorLabels" -}}
   app: {{ .Chart.Name }}
   release: {{ .Release.Name }}
   managed-by: "helm"
   {{- end -}}
   ```

   The function list defines what `default` replaces: "if `.Bar` evaluates to a non-empty value, it will be used. But if it is empty, `foo` will be returned instead.", with `""` as a string's empty value.
   A custom name also goes through `trunc 63` and `trimSuffix "-"`, so it gets the same length limit as the default.

   The guide also says when `default` fits: "In an actual chart, all static default values should live in the `values.yaml`, and should not be repeated using the `default` command (otherwise they would be redundant). However, the `default` command is perfect for computed values, which cannot be declared inside `values.yaml`."
   Our fallback is a computed value.

   **Delete the old block, don't comment it out with `#`:** to the template engine, `#` is plain text, so the actions after it still run (see **23 - Template syntax basics**).
   With the three lines prefixed by `# ` and the variable renamed, `customName: ''` renders without an error, but the name is gone:

   ```yaml
   metadata:
     name: 
   #release-name-go-templating-deep-dive
   ```

   The `{{-` on the `if` line trims the space after `#`, so the name ends up in a YAML comment.
   `helm lint` only warns that the name doesn't conform, and `helm template … | kubectl -n default apply --dry-run=server -f -` rejects the Deployment with `resource name may not be empty`.
   With a custom name set, the assignment runs and the render fails with `undefined variable: $fullName`.
   To keep the lines, wrap them in a Go comment, `{{/* … */}}`.

7. **Compare with the Inline Form:**

   The variable can be inlined, with parentheses around the `printf` call:

   ```yaml
   {{- .Values.customName | default (printf "%s-%s" .Release.Name .Chart.Name) | trunc 63 | trimSuffix "-"  -}}
   ```

   The output is the same, but the pipeline is longer and harder to read; the variable gives the intermediate value a name.

## Conclusion

In this exercise, we declared a variable with `:=`, reassigned it with `=` inside an `if`, and then replaced the `if` with `default`, which handles an empty value in one pipeline.
A `$` followed by a name is a variable; to find its value, look for where it's declared and reassigned nearby.
