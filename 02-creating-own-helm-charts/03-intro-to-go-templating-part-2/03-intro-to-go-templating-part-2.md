# Introduction to Go Templating in Helm

## Overview

In this guide, we’ll be diving into Go templating, its functions, and how to use them within your Helm charts.

In this exercise, we’re going to explore how Go template functions work, and by the end, you should be able to use these functions to transform values in your Helm charts. Here’s a high-level summary of the main steps to follow:

1. Understand the meaning of the dot (`.`) and its context in Helm templating.
2. Familiarize yourself with the top-level objects, starting with `.Values`, `.Release`, and `.Chart`.
3. Learn how to call functions: the function name followed by its arguments, without parentheses.
4. Experiment with the `lower` and `replace` functions.
5. Use the pipe operator to chain function calls, and see when their order matters.

## Step-by-Step Guide

Run the commands from this folder. The chart in `intro-go-templating/` is the end state of this exercise.
It continues from exercise 02's chart, so to follow the steps, copy `../02-intro-to-go-templating-part-1/intro-go-templating` into an empty directory and edit that copy.

1. **Explore the Dot:**

   In `{{ .Values.test }}`, the leading dot is the current context. At the top level of a template, it's the root object Helm passes to every template, and `.Values`, `.Release`, and `.Chart` are three of its fields.

   Helm's built-in objects documentation lists the others: `.Files`, `.Capabilities`, `.Template`, and `.Subcharts`.
   All of them start with a capital letter: "The built-in values always begin with a capital letter. This is in keeping with Go's naming convention."

   The dot changes inside `range` and `with` blocks, which set it to the current element or value. An `if` block leaves it unchanged. Exercises in the Go templating section cover these blocks.

2. **Inspect the Built-in Objects:**

   `.Values` holds the values from `values.yaml` and from the user. To see what `.Release`, `.Chart`, `.Template`, and `.Capabilities` hold, add these four lines to `sandbox.yaml` temporarily:

   ```yaml
   release-info: {{ .Release.Name }} {{ .Release.Namespace }} {{ .Release.Revision }} {{ .Release.IsInstall }} {{ .Release.Service }}
   chart-info: {{ .Chart.Name }} {{ .Chart.Version }} {{ .Chart.AppVersion }}
   template-info: {{ .Template.Name }}
   kube-version: {{ .Capabilities.KubeVersion }}
   ```

   ```bash
   helm template intro-go-templating
   ```

   ```text
   release-info: release-name default 1 true Helm
   chart-info: intro-go-templating 0.1.0 0.1.0
   template-info: intro-go-templating/templates/sandbox.yaml
   kube-version: v1.37.0
   ```

   `helm template` installs nothing, so the `.Release` fields are placeholders: the name is `release-name` unless you pass one, and the namespace is `default` unless you pass `-n`.
   The `.Chart` fields come from `Chart.yaml`, with Go-style capitalized names, so `appVersion` becomes `.Chart.AppVersion`.

   `.Template.Name` is the path of the template being rendered.
   `.Capabilities` describes the cluster, but `helm template` doesn't contact one: "Any values that would normally be looked up or retrieved in-cluster will be faked locally."
   So `.Capabilities.KubeVersion` is v1.37.0, the Kubernetes version Helm 4.3.2 was built against, not k3d-argocd's 1.35; `--kube-version 1.35.5` sets it explicitly. Remove the four lines again.

3. **Learn the Function Syntax:**

   Add a Go comment that records the syntax, below the existing one:

   ```yaml
   {{- /* <function name> <arg1> <arg2> ... */}}
   ```

   Helm's documentation gives the syntax as `functionName arg1 arg2...`: the function name, then its arguments, separated by spaces, with no parentheses and no commas.

4. **Use the `lower` Function:**

   `lower` takes one argument and returns it in lowercase:

   ```yaml
   test: {{ lower .Values.test }}
   ```

   `helm template intro-go-templating` now renders `test: i am a string`.

5. **Use the `replace` Function:**

   `replace` takes three arguments, in this order: the string to replace, the string to replace it with, and the source string. Replace each space with a dash:

   ```yaml
   test: {{ replace " " "-" .Values.test }}
   ```

   The output is `test: I-am-a-string`.

6. **Combine `replace` and `lower`:**

   To lowercase the result of `replace`, it isn't enough to write `lower` in front of it. `lower replace " " "-" .Values.test` passes four arguments to `lower`, and the render fails:

   ```text
   Error: intro-go-templating/templates/sandbox.yaml:4:9
     executing "intro-go-templating/templates/sandbox.yaml" at <lower>:
       wrong number of args for lower: want 1 got 4
   ```

   Parentheses group the `replace` call into a single argument:

   ```yaml
   test: {{ lower (replace " " "-" .Values.test) }}
   ```

   The output is `test: i-am-a-string`.

7. **Use the Pipe Operator:**

   The pipe passes the result of the command on its left to the command on its right.
   The Go `text/template` docs define where it goes: "In a chained pipeline, the result of each command is passed as the last argument of the following command." The same result without parentheses:

   ```yaml
   test: {{ replace " " "-" .Values.test | lower }}
   ```

   The functions can also run in the opposite order. Here `.Values.test` is lowercased first, and the pipe passes the result to `replace` as its last argument, the source string, so `replace` gets only the other two.
   This is the file in `intro-go-templating/templates/sandbox.yaml`:

   ```yaml
   # I am a YAML comment, and I will remain in the generated YAML
   {{- /* I am a GO comment, and I will NOT remain. */}}
   {{- /* <function name> <arg1> <arg2> ... */}}
   test: {{ lower .Values.test | replace " " "-" }}
   labels:
     {{- /* The app label comes from the Release */}}
     app: {{ .Release.Name }}
     {{- /* The chart label comes from the Chart information */}}
     chart: {{ .Chart.Name }}
   ```

   ```text
   ---
   # Source: intro-go-templating/templates/sandbox.yaml
   # I am a YAML comment, and I will remain in the generated YAML
   test: i-am-a-string
   labels:
     app: release-name
     chart: intro-go-templating
   ```

   Both orders give `i-am-a-string`, because lowercasing doesn't change spaces.
   Helm's documentation calls the piped form common: "Inverting the order is a common practice in templates. You will see `.val | quote` more often than `quote .val`. Either practice is fine."

8. **See When the Order Matters:**

   The order matters when one function changes what the other looks for. Replace the capital `I` with `E`, once after lowercasing and once before:

   ```yaml
   test: {{ lower .Values.test | replace "I" "E" }}
   ```

   ```yaml
   test: {{ replace "I" "E" .Values.test | lower }}
   ```

   The first renders `test: i am a string`: by the time `replace` runs, there's no capital `I` left to replace. The second renders `test: e am a string`. Afterwards, revert the line to the version from step 7.

## Conclusion

To summarize, Go templating in Helm relies on the context provided by the dot (`.`), on functions, and on the pipe operator that chains them. Each of these elements plays a key role in customizing and managing your Helm charts.
