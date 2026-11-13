# Introduction to Go Templating

## Overview

In this exercise, we will lay the groundwork for understanding how to effectively use Go templating when working with Helm charts.
As we go through the process of creating, packaging, and publishing charts, you'll find that Go templating is an essential tool that you'll frequently use.

Here's what you'll aim to achieve:

1. Create a new directory for your Helm chart.
2. Set up the necessary files: `Chart.yaml`, `values.yaml`, and a `templates` directory.
3. Add basic information to the `Chart.yaml` file.
4. Create a simple template file within the `templates` directory.
5. Add values in the `values.yaml` file and use them in the template.
6. Run the `helm template` command to see the results.
7. Compare YAML comments with Go comments, and trim the empty lines Go comments leave behind.

## Step-by-Step Guide

Run the commands from this folder. The finished chart is already in `intro-go-templating/`, so the steps describe its files.
To build the chart yourself, run the steps in an empty directory instead, then compare your files with the ones here.

1. **Create a New Directory:**

   ```bash
   mkdir intro-go-templating
   ```

2. **Set Up Necessary Files:**

   Create `Chart.yaml`, `values.yaml`, and a `templates` directory:

   ```bash
   touch intro-go-templating/Chart.yaml intro-go-templating/values.yaml
   mkdir intro-go-templating/templates
   ```

3. **Edit `Chart.yaml`:**

   Add the following details:

   ```yaml
   apiVersion: v2
   name: intro-go-templating
   version: 0.1.0
   appVersion: 0.1.0
   ```

   The chart deploys no application. It's a sandbox for trying out Go template syntax, so `appVersion` is only a placeholder.

4. **Render the Empty Chart:**

   ```bash
   helm template intro-go-templating
   ```

   The command succeeds and prints nothing, because `templates/` holds no files yet.

5. **Create a Template File:**

   Within the `templates` directory, create a file named `sandbox.yaml` with the following line, then render the chart again:

   ```yaml
   test: true
   ```

   ```text
   ---
   # Source: intro-go-templating/templates/sandbox.yaml
   test: true
   ```

   > **Not a Kubernetes object:** `sandbox.yaml` has no `apiVersion` or `kind`, so this chart is only for `helm template`.
   > `helm lint` passes with a warning about the object name, and `helm install --dry-run=client` doesn't notice the problem either.
   > A real install fails: `helm install --dry-run=server` stops with `unable to build kubernetes objects from release manifest: error validating "": error validating data: [apiVersion not set, kind not set]`.

6. **Add Values to `values.yaml`:**

   ```yaml
   test: I am a string
   ```

7. **Use the Value in `sandbox.yaml`:**

   Replace `true` with the value from `values.yaml`:

   ```yaml
   test: {{ .Values.test }}
   ```

   The double curly braces delimit an action. Helm evaluates `.Values.test`, which comes from `values.yaml` or from values passed at install time, and writes the result in place of the action.

8. **Test the Output:**

   ```bash
   helm template intro-go-templating
   ```

   The output now reads `test: I am a string`.

9. **Use Comments:**

   Add a YAML comment and a Go comment at the top of `sandbox.yaml`:

   ```yaml
   # I am a YAML comment, and I will remain in the generated YAML
   {{/* I am a GO comment, and I will NOT remain. */}}
   test: {{ .Values.test }}
   ```

   The YAML comment stays in the output. The Go comment is removed, but its line stays behind as an empty line:

   ```text
   ---
   # Source: intro-go-templating/templates/sandbox.yaml
   # I am a YAML comment, and I will remain in the generated YAML

   test: I am a string
   ```

   A Go comment has to start and end at the delimiters. The Go `text/template` docs say: "Comments do not nest and must start and end at the delimiters, as shown here."
   With spaces inside the braces, `{{ /* … */ }}`, the render fails with `parse error at (intro-go-templating/templates/sandbox.yaml:2): unexpected "/" in command`.

10. **Add Labels with Go Comments:**

    Add labels that come from the release and the chart, each with a Go comment above it:

    ```yaml
    labels:
      {{/* The app label comes from the Release */}}
      app: {{ .Release.Name }}
      {{/* The chart label comes from the Chart information */}}
      chart: {{ .Chart.Name }}
    ```

    Each Go comment leaves another empty line:

    ```text
    labels:

      app: release-name

      chart: intro-go-templating
    ```

    `helm template` names the release `release-name` unless you pass a name: `helm template my-sandbox intro-go-templating` renders `app: my-sandbox`.

11. **Trim Whitespace:**

    A dash right after the opening braces trims all whitespace before the action, including the newline that ends the previous line.
    Add it, followed by a space, to every Go comment. This is the file in `intro-go-templating/templates/sandbox.yaml`:

    ```yaml
    # I am a YAML comment, and I will remain in the generated YAML
    {{- /* I am a GO comment, and I will NOT remain. */}}
    test: {{ .Values.test }}
    labels:
      {{- /* The app label comes from the Release */}}
      app: {{ .Release.Name }}
      {{- /* The chart label comes from the Chart information */}}
      chart: {{ .Chart.Name }}
    ```

    The empty lines are gone:

    ```text
    ---
    # Source: intro-go-templating/templates/sandbox.yaml
    # I am a YAML comment, and I will remain in the generated YAML
    test: I am a string
    labels:
      app: release-name
      chart: intro-go-templating
    ```

    The space after the dash is required. The Go docs: "In these trim markers, the white space must be present: "{{- 3}}" is like "{{3}}" but trims the immediately preceding text, while "{{-3}}" parses as an action containing the number -3."
    Without it, `{{-/* … */}}` fails with `parse error at (intro-go-templating/templates/sandbox.yaml:2): "-"`.

    A dash before the closing braces, ` -}}`, trims the whitespace after the action instead.

    On the comment above `app`, `{{- /* … */ -}}` trims on both sides, so `app:` moves up onto the `labels:` line.
    The render fails with `YAML parse error on intro-go-templating/templates/sandbox.yaml: error converting YAML to JSON: yaml: line 4: mapping values are not allowed in this context`.

    The next section shows each dash position with the whitespace made visible.

## How the Dashes Trim Whitespace

Helm copies every character outside `{{ }}` to the output, including spaces and newlines.
A Go comment outputs nothing, but the spaces before it and the newline after it are ordinary text, so they stay.
A dash next to the braces deletes the whitespace on that side of the action.

In the examples below, `·` stands for a space and `⏎` for a newline. Each output is what `helm template` renders for that source.

**No dash:** the comment disappears, but its indentation and the newline after it remain, and they render as a line of two spaces. The source:

```text
labels:⏎
··{{/* c */}}⏎
··app:·x⏎
```

The output:

```text
labels:⏎
··⏎
··app:·x⏎
```

**`{{-`, a dash after the opening braces:** deletes every space, tab, and newline to the left of the action, back to the last visible character, here the `:` of `labels:`.
The newline after the comment stays and becomes the line break before `app`:

```text
labels:⏎
··app:·x⏎
```

**` -}}`, a dash before the closing braces:** deletes the whitespace to the right of the action, up to the next visible character, here the `a` of `app`.
The two spaces before the comment stay and become `app`'s indentation, so the result is the same:

```text
labels:⏎
··app:·x⏎
```

**Dashes on both sides:** delete both gaps, so `app:` joins `labels:` on one line. That isn't valid YAML, which is the error at the end of step 11:

```text
labels:app:·x⏎
```

The Go `text/template` docs give a one-line example: `{{23 -}} < {{- 45}}` renders as `23<45`. The first action's ` -}}` deletes the space before `<`, and the second action's `{{-` deletes the space after it.

**The space after the dash:** `{{- 3}}` trims to the left and prints `3`, while `{{-3}}` has no space, so Go reads `-3` as the number -3 and prints `-3`.
The same applies to `{{-/*`: without the space there is no trim marker, the comment no longer starts at the delimiter, and parsing fails.

**Rule of thumb:** for a line that outputs nothing, such as a comment, or the `if`, `else`, and `end` actions in later exercises, start the action with `{{-`.
It deletes the line's own indentation and the newline before it, so the line leaves nothing behind.
Use ` -}}` only when the next line should move up, and don't put dashes on both sides of a line that sits between two lines you want to keep.

## Conclusion

In this exercise, we explored the fundamentals of Go templating, from setting up a simple Helm chart to using values, comments, and whitespace trimming.
YAML is indentation-sensitive, so trimming whitespace and getting indentation right comes up in almost every Helm chart.
