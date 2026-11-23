# Accessing a file from a chart

## Overview

In this exercise, we'll create a small chart, `accessing-files`, whose ConfigMap loads a file from the chart with `.Files.Get`, and remove the blank line that `nindent` adds in front of it.
Here's a quick summary of the main steps:

1. Create the chart's directories and `Chart.yaml`.
2. Add a ConfigMap, named by a `fullname` helper.
3. Load `files/application.properties` into the ConfigMap with `.Files.Get`.
4. Remove the extra blank line.

## Step-by-step guide

Run the commands from this folder. The chart in `accessing-files/` is the end state of this exercise; to build it yourself, run the steps in an empty directory.

1. **Create the chart:**

   ```bash
   mkdir -p accessing-files/templates accessing-files/files
   ```

   The name `files/` is only a convention. The accessing files guide puts one directory out of reach: *"Files in `templates/` cannot be accessed."*

   Create `accessing-files/Chart.yaml`:

   ```yaml
   apiVersion: v2
   name: accessing-files
   description: Demo for accessing files from within the chart
   type: application
   version: 0.1.0
   appVersion: '1.0.0'
   ```

   The chart has no `values.yaml`; `helm lint accessing-files` reports `[INFO] values.yaml: file does not exist` and passes.

2. **Add a ConfigMap:**

   Create `templates/configmap.yaml`:

   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: {{ include "accessing-files.fullname" . }}
   ```

   For the name, copy the `fullname` helper and its comment from config-store's `_helpers.tpl` into `templates/_helpers.tpl`, and rename it to `accessing-files.fullname`. It reads `.Values.fullnameOverride` and `.Values.nameOverride`, which stay empty here.

   ```bash
   helm template accessing-files
   ```

   ```text
   ---
   # Source: accessing-files/templates/configmap.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: release-name-accessing-files
   ```

3. **Load a file:**

   Create `files/application.properties`, a Spring Boot style configuration:

   ```properties
   server.port=8080

   logging.level.root=INFO
   ```

   Add a `data` section to the ConfigMap, with the file's contents as a multi-line string:

   ```yaml
   data:
     application.properties: |-
   {{ .Files.Get "files/application.properties" | nindent 4 }}
   ```

   `.Files.Get` takes a path from the chart's root, and returns the file's contents as they are. The accessing files guide describes the use: *"inject its contents without sending the contents through the template renderer."*

   ```text
   data:
     application.properties: |-

       server.port=8080

       logging.level.root=INFO
   ```

   **`nindent` adds a blank line:** it starts with a newline, and the action already sits on a line of its own. The blank line becomes part of the value, which YAML reads as `'\nserver.port=8080\n\nlogging.level.root=INFO'`.

4. **Remove the blank line:**

   Either of two changes removes it:

   | Line | Why it works |
   |---|---|
   | `{{- .Files.Get "files/application.properties" \| nindent 4 }}` | the `{{-` removes the newline before the action, and `nindent` adds one back |
   | `{{ .Files.Get "files/application.properties" \| indent 4 }}` | `indent` adds no newline |

   The chart in this folder uses `indent`. Both render the same:

   ```text
   data:
     application.properties: |-
       server.port=8080

       logging.level.root=INFO
   ```

   The value is now `'server.port=8080\n\nlogging.level.root=INFO'`, and `|-` keeps it without a final newline. `helm template accessing-files | kubectl -n default apply --dry-run=server -f -` reports `configmap/release-name-accessing-files created (server dry run)`.

   **A wrong path fails silently:** `.Files.Get "files/missing.properties"` renders an empty value, without an error.

   **Files outside the chart come in as values:** `.Files` reads only files packaged with the chart. The accessing files guide gives the option for any other file: *"To supply the contents of a file outside the chart as a value, use `--set-file`"*, as in `helm template accessing-files --set-file config=./config.ini`, which the templates then read as `.Values.config`.

## Conclusion

In this exercise, we loaded a file packaged with the chart into a ConfigMap with `.Files.Get`, and removed the blank line in front of it with `indent` or `{{-`.
Exercise 02 loads several files at once with glob patterns.
