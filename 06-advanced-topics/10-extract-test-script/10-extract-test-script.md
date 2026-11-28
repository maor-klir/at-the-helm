# Extracting the test script

## Overview

In this exercise, we'll move the test's logic out of the test Pod into a shell script, `files/test-scripts/run.sh`, and load it into a ConfigMap that the test Pod can mount in exercise 11.
Here's a quick summary of the main steps:

1. Add a ConfigMap, created as a `test` hook, that loads every file under `files/test-scripts/`.
2. Write the test script, with template actions for the Service's name and port.
3. Render the script's template actions with `tpl`.
4. See why the script can't live under `templates/`.

## Step-by-step guide

Run the commands from this folder. The chart in `test-hook/` is the end state of this exercise, and continues from exercise 09's chart.
To build it yourself, copy exercise 09's `test-hook` into an empty directory, and run the steps there. This exercise only renders the chart.

1. **Add a ConfigMap for the test files:**

   Create `templates/tests/test-files.yaml`. The `test` hook makes Helm create the ConfigMap when `helm test` runs, together with the test Pod:

   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: {{ include "test-hook.fullname" . }}-test-files
     annotations:
       "helm.sh/hook": test
   data:
   {{ (.Files.Glob "files/test-scripts/*").AsConfig | indent 2 }}
   ```

   Exercise 11 gives the test objects weights, and exercise 12 a deletion policy.

2. **Write the test script:**

   Create `files/test-scripts/run.sh`, at the chart's root, outside `templates/`. The script installs `curl` in an Alpine container, and requests the chart's Service:

   ```sh
   #!/bin/sh

   echo "Installing curl..."
   apk update && apk add --no-cache curl

   echo "Executing curl request to {{ .Release.Name }}"
   curl http://{{ include "test-hook.fullname" . }}:{{ .Values.service.port }}
   ```

   The template actions don't render yet:

   ```bash
   helm template local-test-hook test-hook --show-only templates/tests/test-files.yaml
   ```

   ```text
   data:
     run.sh: |-
       #!/bin/sh

       echo "Installing curl..."
       apk update && apk add --no-cache curl

       echo "Executing curl request to {{ .Release.Name }}"
       curl http://{{ include "test-hook.fullname" . }}:{{ .Values.service.port }}
   ```

   The ConfigMap's own name renders as `local-test-hook-test-files`, but `.AsConfig` copies the file's content as it is (see **61 - Accessing files in a chart**).

3. **Render the script with `tpl`:**

   The `tpl` function renders a string as a template. The chart tips and tricks guide: *"The `tpl` function allows developers to evaluate strings as templates inside a template."*
   Its syntax is `{{ tpl TEMPLATE_STRING VALUES }}`: two arguments, the string to render and the context to render it with.

   ```yaml
   data:
   {{ tpl (.Files.Glob "files/test-scripts/*").AsConfig . | indent 2 }}
   ```

   | Argument | Here |
   |---|---|
   | `TEMPLATE_STRING` | `(.Files.Glob "files/test-scripts/*").AsConfig`, the script as text |
   | `VALUES` | `.`, the chart's top-level object, which holds `.Release`, `.Values`, `.Chart`, and the named templates |

   The script's `{{ .Release.Name }}` and `{{ .Values.service.port }}` are resolved against that second argument:

   ```text
       echo "Executing curl request to local-test-hook"
       curl http://local-test-hook:80
   ```

   Without the `.`, the render fails with `wrong number of args for tpl: want 2 got 1`.
   `tpl` renders the whole `.AsConfig` output, so every file the pattern matches can use `.Values`, `.Release`, and the chart's named templates.
   A server-side dry run, `helm template local-test-hook test-hook | kubectl -n default apply --dry-run=server -f -`, accepts the ConfigMap with the rest of the chart.

4. **See why the script lives in `files/`:**

   Helm renders every file under `templates/` as a manifest. A copy of `run.sh` at `templates/tests/random.sh` stops the render:

   ```text
   Error: YAML parse error on test-hook/templates/tests/random.sh: error unmarshaling JSON: while decoding JSON: json: cannot unmarshal string into Go value of type util.SimpleHead
   ```

   `helm lint test-hook` names the reason: `file extension '.sh' not valid. Valid extensions are .yaml, .yml, .tpl, or .txt`. Delete `random.sh` again.

## Conclusion

In this exercise, we moved the test's logic into `files/test-scripts/run.sh`, loaded it into a ConfigMap with `.Files.Glob` and `.AsConfig`, and rendered its template actions with `tpl`.
Exercise 11 mounts the ConfigMap in the test Pod and runs the script.
