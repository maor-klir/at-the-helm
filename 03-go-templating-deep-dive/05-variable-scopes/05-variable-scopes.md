# Understanding Variable Scope in Helm Templates

## Overview

In this exercise, we'll see where a variable can be used: only inside the block that declares it, and in the blocks nested in it.
Here's what we'll aim to implement:

1. Use a named template's variable in the Deployment, and read the error.
2. Declare a variable in the branches of an `if` and `else`, and use it after the `end`.
3. Declare the variable before the `if`, and reassign it inside.
4. See what `:=` does inside the `if` instead of `=`.

## Step-by-Step Guide

Run the commands from this folder. This exercise ends where exercise 04 ends, so it has no chart copy of its own.
To follow the steps, copy `../04-variables/go-templating-deep-dive` into an empty directory and edit that copy.

1. **Use a Variable Outside Its Template:**

   In `templates/deployment.yaml`, add a placeholder label under `metadata.labels` that reads `$defaultName`, the variable from the `fullname` named template:

   ```yaml
       {{- include "go-templating-deep-dive.selectorLabels" . | nindent 4 }}
       placeholder: {{ $defaultName }}
   ```

   ```bash
   helm template go-templating-deep-dive
   ```

   ```text
   Error: parse error at (go-templating-deep-dive/templates/deployment.yaml:7): undefined variable "$defaultName"
   ```

   The Go template syntax defines how far a variable reaches: "A variable's scope extends to the "end" action of the control structure ("if", "with", or "range") in which it is declared, or to the end of the template if there is no such control structure."
   `$defaultName` is declared in the `define` block, so it ends at the `define`'s `end`. It's a parse error, so Helm reports it with the file and line before rendering anything.

   The other direction fails too: "A template invocation does not inherit variables from the point of its invocation."
   A variable declared in `deployment.yaml` before the `include` is undefined inside the named template, and so is one declared in `_helpers.tpl` outside the `define`.
   A named template gets its values only from its context (see **32 - Named templates**).

   Remove the placeholder label.

2. **Declare the Variable Inside `if` and `else`:**

   In `templates/_helpers.tpl`, build the name with `if` and `else`, and declare `$fullName` with `:=` in each branch:

   ```yaml
   {{- define "go-templating-deep-dive.fullname" -}}
   {{- if .Values.customName }}
   {{- $fullName := .Values.customName }}
   {{- else }}
   {{- $fullName := printf "%s-%s" .Release.Name .Chart.Name }}
   {{- end }}
   {{- $fullName | trunc 63 | trimSuffix "-"  -}}
   {{- end -}}
   ```

   ```text
   Error: parse error at (go-templating-deep-dive/templates/_helpers.tpl:7): undefined variable "$fullName"
   ```

   Line 7 is the pipeline after the `end`. Each `$fullName` exists only inside its branch, so neither is left when the pipeline uses it.

3. **Declare Before, Reassign Inside:**

   Declare `$fullName` before the `if`, and reassign it inside with `=`, as in exercise 04:

   ```yaml
   {{- define "go-templating-deep-dive.fullname" -}}
   {{- $fullName := printf "%s-%s" .Release.Name .Chart.Name }}
   {{- if .Values.customName }}
   {{- $fullName = .Values.customName }}
   {{- end }}
   {{- $fullName | trunc 63 | trimSuffix "-"  -}}
   {{- end -}}
   ```

   ```bash
   helm template go-templating-deep-dive --set customName=my-custom-release
   ```

   The render succeeds, and the Deployment is named `my-custom-release`.
   `$fullName` is now declared at the level of the `define`, so its scope runs to the `define`'s `end`, and the `if` nested inside can reassign it.

4. **See What `:=` Does Inside the `if`:**

   Change the assignment inside the `if` to `:=`:

   ```yaml
   {{- $fullName := .Values.customName }}
   ```

   Render again with `--set customName=my-custom-release`. There's no error, but the Deployment is named `release-name-go-templating-deep-dive`: the custom name is ignored.
   `:=` declares a second `$fullName` that hides the first one until the `end` and is then gone, so the pipeline after the `end` uses the unchanged first one.

5. **Revert to the `default` Version:**

   Restore the named template from exercise 04, which needs no `if`:

   ```yaml
   {{- define "go-templating-deep-dive.fullname" -}}
   {{- $defaultName := printf "%s-%s" .Release.Name .Chart.Name }}
   {{- .Values.customName | default $defaultName | trunc 63 | trimSuffix "-"  -}}
   {{- end -}}
   ```

## Conclusion

In this exercise, we saw that a variable lives until the `end` of the block that declares it, is visible in the blocks nested in it, and never crosses into another template.
To change a variable inside an `if`, declare it before the `if` and reassign it with `=`; the same rules apply to the `range` and `with` blocks in the next exercises.
