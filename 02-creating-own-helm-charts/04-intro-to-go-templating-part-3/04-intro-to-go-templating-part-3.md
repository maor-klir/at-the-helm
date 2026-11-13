# Introduction to Go Templating

## Overview

In this session, we’ll dive into how you can use conditionals to make your templates more dynamic and flexible.

Here’s what you’ll aim to implement:

1. Add an `environment` value to your `values.yaml` file.
2. Write an `if` condition in your template that checks whether the environment is `production`.
3. Render different labels for production and for other environments, using `if`, `else`, and `end`.
4. Remove the empty line the conditional leaves behind, using dashes.

## Step-by-Step Guide

Run the commands from this folder. The chart in `intro-go-templating/` is the end state of this exercise.
It continues from exercise 03's chart, so to follow the steps, copy `../03-intro-to-go-templating-part-2/intro-go-templating` into an empty directory and edit that copy.

1. **Add an Environment Value:**

   Add an `environment` key to `values.yaml`:

   ```yaml
   test: I am a string
   environment: production
   ```

2. **Write the Condition:**

   Add these lines to the end of `sandbox.yaml`, under `labels`:

   ```yaml
     {{ if eq .Values.environment "production" }}
     environment: production
     build: stable
     public-ingress: true
     {{ else }}
     environment: dev
     build: alpha
     public-ingress: false
     {{ end }}
   ```

   `eq` comes first because it's a function, not an operator placed between two values.
   Helm's documentation says: "For templates, the operators (`eq`, `ne`, `lt`, `gt`, `and`, `or` and so on) are all implemented as functions."

   `eq` also takes more than two arguments, and is true if the first one equals any of the others: `eq .Values.environment "production" "prod"` matches both values. Every `if` is closed with an `end`.

3. **Render the Template:**

   ```bash
   helm template intro-go-templating
   ```

   Only the production labels are rendered. The `if` action outputs nothing, but its line stays behind as an empty line:

   ```text
   labels:
     app: release-name
     chart: intro-go-templating

     environment: production
     build: stable
     public-ingress: true
   ```

4. **Switch the Environment:**

   Set `environment: staging` in `values.yaml` and render again, or override the value without editing the file: `helm template intro-go-templating --set environment=staging`.
   The `else` branch renders now:

   ```text
     environment: dev
     build: alpha
     public-ingress: false
   ```

   Any value other than `production` renders the `else` branch. So does a missing value: without the `environment` key, `eq` returns false instead of failing.

5. **Remove the Empty Line:**

   Add a dash to the opening braces of `if`, `else`, and `end`, so each one trims the newline and indentation before it (see the "How the Dashes Trim Whitespace" section of exercise 02).
   This is the file in `intro-go-templating/templates/sandbox.yaml`, with `environment: staging` in `values.yaml`:

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
     {{- if eq .Values.environment "production" }}
     environment: production
     build: stable
     public-ingress: true
     {{- else }}
     environment: dev
     build: alpha
     public-ingress: false
     {{- end }}
   ```

   ```text
   ---
   # Source: intro-go-templating/templates/sandbox.yaml
   # I am a YAML comment, and I will remain in the generated YAML
   test: i-am-a-string
   labels:
     app: release-name
     chart: intro-go-templating
     environment: dev
     build: alpha
     public-ingress: false
   ```

6. **Chain Conditions with `else if`:**

   An `else` can start another condition directly.
   The Go `text/template` docs: "To simplify the appearance of if-else chains, the else action of an if may include another if directly".
   To try it, replace the condition in your copy with:

   ```yaml
     {{- if eq .Values.environment "production" }}
     environment: production
     {{- else if eq .Values.environment "staging" }}
     environment: staging
     {{- else }}
     environment: dev
     {{- end }}
   ```

   With `environment: staging`, this renders `environment: staging`. The chart in this folder keeps the `if`/`else` version from step 5.

## Conclusion

By implementing conditionals in your Helm templates, you can render different output depending on the values.
Conditionals, loops, and the other control structures come back in more depth in the Go templating section.
