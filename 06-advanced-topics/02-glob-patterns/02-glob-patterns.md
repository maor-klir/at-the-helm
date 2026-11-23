# Loading files with glob patterns

## Overview

In this exercise, we'll load every `.properties` file under `files/` into the ConfigMap with one `range` over `.Files.Glob`, instead of one entry per file.
Here's a quick summary of the main steps:

1. Add `dev.properties` and `prod.properties`, and load each with its own entry.
2. Replace the entries with a `range` over `.Files.Glob`, and reach `.Files` through `$` inside it.
3. Trim the whitespace, and use `base` for the keys.
4. Add a fourth file without changing the template.

## Step-by-step guide

Run the commands from this folder. The chart in `accessing-files/` is the end state of this exercise, and continues from exercise 01's chart.
To build it yourself, copy exercise 01's `accessing-files` into an empty directory, and run the steps there.

1. **Add two files:**

   Create `files/dev.properties`:

   ```properties
   server.port=8080

   logging.level.root=DEBUG
   ```

   And `files/prod.properties`:

   ```properties
   server.port=8081

   logging.level.root=INFO
   ```

   Repeating the entry from exercise 01 for each file works:

   ```yaml
     dev.properties: |-
   {{ .Files.Get "files/dev.properties" | indent 4 }}
     prod.properties: |-
   {{ .Files.Get "files/prod.properties" | indent 4 }}
   ```

   `helm template accessing-files` renders three entries, but every new file needs another two lines in the template.

2. **Loop over the files:**

   Replace the whole `data` section with a loop over the files that `files/*.properties` matches:

   ```yaml
   data:
   {{ range $path, $_ := .Files.Glob "files/*.properties" }}
     {{ $path }}: |-
   {{ .Files.Get $path | indent 4 }}
   {{ end }}
   ```

   The accessing files guide: *"`.Glob` returns a `Files` type, so you may call any of the `Files` methods on the returned object."* The loop's key is the file's path, and its value, ignored here as `$_`, is the file's contents.

   ```text
   Error: accessing-files/templates/configmap.yaml:8:9
     executing "accessing-files/templates/configmap.yaml" at <.Files.Get>:
       can't evaluate field Files in type []uint8
   ```

   Inside `range`, the dot is the current value, a file's contents as bytes (`[]uint8`), which has no `Files` field. `$` still points to the top-level object, so `$.Files.Get $path` works (see **35 - The dot and with blocks**).

3. **Fix the keys and the whitespace:**

   With `$.Files.Get`, the template renders, with two problems: a blank line before each entry, and keys such as `files/dev.properties`.
   The API server rejects those keys: `helm template accessing-files | kubectl -n default apply --dry-run=server -f -` reports, for each one:

   ```text
   a valid config key must consist of alphanumeric characters, '-', '_' or '.' (e.g. 'key.name',  or 'KEY_NAME',  or 'key-name', regex used for validation is '[-._a-zA-Z0-9]+')
   ```

   `base` returns the last element of a path. The guide explains where it comes from: *"Helm imports many of the functions from Go's path package for your use."* Add it, and `{{-` to the `range` and `end` lines:

   ```yaml
   data:
   {{- range $path, $_ := .Files.Glob "files/*.properties" }}
     {{ base $path }}: |-
   {{ $.Files.Get $path | indent 4 }}
   {{- end }}
   ```

   ```text
   data:
     application.properties: |-
       server.port=8080

       logging.level.root=INFO
     dev.properties: |-
       server.port=8080

       logging.level.root=DEBUG
     prod.properties: |-
       server.port=8081

       logging.level.root=INFO
   ```

   `range` lists the files in alphabetical order. In the pattern, `*` stays within `files/`; `files/**.properties` would also match files in its subfolders, and `files/{dev,prod}.properties` only those two.

4. **Add a fourth file:**

   Create `files/another.properties`:

   ```properties
   server.port=8081

   logging.level.root=ERROR
   ```

   The template doesn't change, and the render has a fourth entry, `another.properties`, first in alphabetical order. The server-side dry run now reports `configmap/release-name-accessing-files created (server dry run)`.

## Conclusion

In this exercise, we loaded every `.properties` file under `files/` with a `range` over `.Files.Glob`, reached `.Files` through `$` inside the loop, and used `base` for valid ConfigMap keys.
Exercise 03 builds the same ConfigMap, and a Secret, with the `Files` utility functions.
