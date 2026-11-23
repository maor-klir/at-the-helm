# ConfigMap and Secret utility functions

## Overview

In this exercise, we'll replace the `range` loop from exercise 02 with `.AsConfig`, one call that turns the matched files into ConfigMap data, and build a Secret from the same files with `.AsSecrets`.
Here's a quick summary of the main steps:

1. Build the ConfigMap's `data` with `(.Files.Glob "files/*.properties").AsConfig`.
2. Add a Secret whose `data` comes from `.AsSecrets`.
3. Check both objects with a server-side dry run.

## Step-by-step guide

Run the commands from this folder. The chart in `accessing-files/` is the end state of this exercise, and continues from exercise 02's chart.
To build it yourself, copy exercise 02's `accessing-files` into an empty directory, and run the steps there.

1. **Build the ConfigMap with `.AsConfig`:**

   In `templates/configmap.yaml`, replace the `range` loop with one line:

   ```yaml
   data:
   {{ (.Files.Glob "files/*.properties").AsConfig | indent 2 }}
   ```

   The parentheses make `.AsConfig` apply to the result of `.Files.Glob`, which is a `Files` object as well.

   ```bash
   helm template accessing-files
   ```

   ```text
   data:
     another.properties: |-
       server.port=8081

       logging.level.root=ERROR
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

   The entries are the same as exercise 02's. `.AsConfig` already uses each file's base name as its key (from Helm's source, `path.Base`), so the template needs no `base`.

2. **Build a Secret with `.AsSecrets`:**

   Create `templates/secret.yaml`:

   ```yaml
   # For demonstration purposes, not recommended
   # as it is in real projects!

   apiVersion: v1
   kind: Secret
   metadata:
     name: {{ include "accessing-files.fullname" . }}
   type: Opaque
   data:
   {{ (.Files.Glob "files/*.properties").AsSecrets | indent 2 }}
   ```

   `.AsSecrets` encodes each file in base64, as a Secret's `data` requires:

   ```text
   data:
     another.properties: c2VydmVyLnBvcnQ9ODA4MQoKbG9nZ2luZy5sZXZlbC5yb290PUVSUk9S
     application.properties: c2VydmVyLnBvcnQ9ODA4MAoKbG9nZ2luZy5sZXZlbC5yb290PUlORk8=
     dev.properties: c2VydmVyLnBvcnQ9ODA4MAoKbG9nZ2luZy5sZXZlbC5yb290PURFQlVH
     prod.properties: c2VydmVyLnBvcnQ9ODA4MQoKbG9nZ2luZy5sZXZlbC5yb290PUlORk8=
   ```

   Decoded, `dev.properties` is `server.port=8080\n\nlogging.level.root=DEBUG`, the file as it is.

   **Not for real secrets:** the files are packaged with the chart, so any secret in them would travel with every copy of it. Base64 is an encoding, not encryption, and the Kubernetes documentation adds a caution about the object itself: *"Kubernetes Secrets are, by default, stored unencrypted in the API server's underlying data store (etcd)."*
   Secrets belong outside the chart, created separately, as `postgres-creds` was for config-store (see **42 - From Compose to a Helm chart**).

3. **Check both objects:**

   ```bash
   helm template accessing-files | kubectl -n default apply --dry-run=server -f -
   ```

   ```text
   secret/release-name-accessing-files created (server dry run)
   configmap/release-name-accessing-files created (server dry run)
   ```

   **Same file names in different folders collide:** with `files/**.properties` and a second `dev.properties` in `files/nested/`, `.AsConfig` rendered a single `dev.properties` key, with the nested file's content.

## Conclusion

In this exercise, we built a ConfigMap's data with `.AsConfig` and a Secret's with `.AsSecrets`, and saw why files packaged with a chart are no place for real secrets.
Exercise 04 starts the hooks part of the section.
