# Making the chart tests configurable

## Overview

In this exercise, we'll move the test objects' hardcoded settings into a `tests` section of `values.yaml`, let users turn the tests off, and make the test objects' delete policy a value, so that a successful run cleans up after itself.
Here's a quick summary of the main steps:

1. Add a `tests` section to `values.yaml`.
2. Render the test objects only when `tests.enabled` is true.
3. Read the test Pod's container and volume settings from the values.
4. Make the delete policy configurable.
5. Upgrade the release, and run the tests.
6. Break the test, and see what stays.
7. Turn the tests off.

## Step-by-step guide

Run the commands from this folder. The chart in `test-hook/` is the end state of this exercise, and continues from exercise 11's chart.
To build it yourself, copy exercise 11's `test-hook` into an empty directory, and run the steps there. The release is `local-test-hook` in the namespace `test-hook`; install it from exercise 11's chart if it isn't there.

1. **Add a `tests` section to `values.yaml`:**

   At the end of `values.yaml`, collect the values that the test templates hardcode:

   ```yaml
   # Test configuration for helm tests
   tests:
     enabled: true
     container:
       nameOverride: ''
       imageRepository: 'alpine'
       imageTag: '3.20'
     scripts:
       volumeName: 'tests'
       volumeMountPath: '/tests'
       runFileName: 'run.sh'
     hookDeletePolicies:
       - before-hook-creation
       - hook-succeeded
   ```

   | Value | Purpose |
   |---|---|
   | `tests.enabled` | renders the test objects only when `true` |
   | `tests.container.nameOverride` | names the test container; when empty, the name is `alpine` |
   | `tests.container.imageRepository`, `tests.container.imageTag` | set the test container's image, `alpine:3.20` |
   | `tests.scripts.volumeName` | names the ConfigMap volume, in both the Pod's `volumes` and the container's `volumeMounts` |
   | `tests.scripts.volumeMountPath` | sets the folder in the container where the ConfigMap's files appear |
   | `tests.scripts.runFileName` | names the script the container runs from that folder |
   | `tests.hookDeletePolicies` | lists when Helm deletes the test objects (step 4) |

   The image is two flat keys, while the scaffold's own `image` section nests `repository` and `tag`. The difference shows when a key is missing.
   With `container: {}`, `{{ .Values.container.imageRepository | default "none" }}` renders `none`, but `{{ .Values.container.image.repository | default "none" }}` fails with `nil pointer evaluating interface {}.repository`: a missing key reads as empty, but a field of a missing key can't be read at all.

   The course's commit also reformats the scaffold's part of `values.yaml`, with single quotes and some `{}` on their own lines. With `--skip-tests`, `helm template` renders the same objects as exercise 11's chart.

2. **Render the test objects only when enabled:**

   Wrap both test templates, `templates/tests/test-connection.yaml` and `templates/tests/test-files.yaml`, in an `if` block:

   ```yaml
   {{- if .Values.tests.enabled }}
   apiVersion: v1
   ...
   {{- end }}
   ```

   With the tests turned off, the chart renders only the ServiceAccount, the Service, and the Deployment:

   ```bash
   helm template local-test-hook test-hook --set tests.enabled=false | grep '^kind'
   ```

   ```text
   kind: ServiceAccount
   kind: Service
   kind: Deployment
   ```

   A template that renders nothing is left out of the output: `--show-only templates/tests/test-connection.yaml` then fails with `Error: could not find template templates/tests/test-connection.yaml in chart`.

3. **Read the test Pod's settings from the values:**

   In `templates/tests/test-connection.yaml`, replace the hardcoded container and volume settings:

   ```yaml
   spec:
     containers:
   {{- with .Values.tests.container }}
       - name: {{ default "alpine" .nameOverride }}
         image: "{{ .imageRepository }}:{{ .imageTag }}"
   {{- end }}
   {{- with .Values.tests.scripts }}
         command: ['sh', '-c', '{{ .volumeMountPath }}/{{ .runFileName }}']
         volumeMounts:
           - mountPath: {{ .volumeMountPath }}
             name: {{ .volumeName }}
   {{- end }}
     restartPolicy: Never
     volumes:
       - name: {{ .Values.tests.scripts.volumeName }}
         configMap:
           name: {{ include "test-hook.fullname" . }}-test-files
           defaultMode: 0744
   ```

   Inside each `with` block, the dot is the value the block names, so `.nameOverride` reads `tests.container.nameOverride` (see **35 - The dot and with blocks**).
   The `{{-` removes the newline and the spaces before each action, so the actions can start at the beginning of the line without changing the output.

   `volumes` stays outside the `with` blocks, because its `include` needs the top-level `.`, so the volume's name takes the full path. Inside a block, `$` would reach the top-level object too.
   The double quotes make sure YAML reads `image` as a string. With the default values, the Pod renders as before:

   ```text
   spec:
     containers:
       - name: alpine
         image: "alpine:3.20"
         command: ['sh', '-c', '/tests/run.sh']
         volumeMounts:
           - mountPath: /tests
             name: tests
     restartPolicy: Never
     volumes:
       - name: tests
   ```

   With `--set tests.container.nameOverride=probe --set tests.scripts.volumeMountPath=/scripts --set tests.scripts.volumeName=scripts`, the container became `probe`, it ran `/scripts/run.sh`, and both the volume and its mount were named `scripts`.

4. **Make the delete policy configurable:**

   In both test templates, add the annotation below `helm.sh/hook-weight`:

   ```yaml
       "helm.sh/hook-delete-policy": {{ .Values.tests.hookDeletePolicies | default (list "before-hook-creation") | join "," }}
   ```

   | Part | Purpose |
   |---|---|
   | `.Values.tests.hookDeletePolicies` | the list of policies from `values.yaml` |
   | `default (list "before-hook-creation")` | when the value is missing or an empty list, uses a list with only `before-hook-creation`, Helm's default policy |
   | `join ","` | joins the list into the comma-separated string the annotation takes; the pipe passes the list as `join`'s last argument |

   ```text
       "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
   ```

   With `hookDeletePolicies` removed from `values.yaml`, or set to `[]`, the annotation renders `before-hook-creation`.
   `before-hook-creation` deletes the previous run's object before Helm creates it again, and `hook-succeeded` deletes it after the run succeeds (see **62 - Chart hooks**).

   Keep `before-hook-creation` in any list a user sets: it's the only policy that deletes a test object left by an earlier run before the next run creates it again.

5. **Upgrade, and run the tests:**

   ```bash
   helm -n test-hook upgrade local-test-hook test-hook
   helm -n test-hook test local-test-hook
   ```

   ```text
   TEST SUITE:     local-test-hook-test-files
   Last Started:   Sat Nov 28 10:49:47 2026
   Last Completed: Sat Nov 28 10:49:47 2026
   Phase:          Succeeded
   TEST SUITE:     local-test-hook-test-connection
   Last Started:   Sat Nov 28 10:49:47 2026
   Last Completed: Sat Nov 28 10:49:55 2026
   Phase:          Succeeded
   ```

   This time, the test objects are gone after the run: `kubectl -n test-hook get pods,configmaps` lists only the Deployment's Pod and `kube-root-ca.crt`.
   `--logs` still prints the test Pod's log, as `helm test --help` describes: *"this runs after all tests are complete, but before any cleanup"*.

6. **Break the test:**

   In `files/test-scripts/run.sh`, point `curl` at a host that doesn't exist:

   ```sh
   curl http://inexistent:{{ .Values.service.port }}
   ```

   Upgrade, and run the tests again:

   ```text
   TEST SUITE:     local-test-hook-test-files
   Last Started:   Sat Nov 28 10:50:23 2026
   Last Completed: Sat Nov 28 10:50:23 2026
   Phase:          Succeeded
   TEST SUITE:     local-test-hook-test-connection
   Last Started:   Sat Nov 28 10:50:23 2026
   Last Completed: Sat Nov 28 10:50:29 2026
   Phase:          Failed
   Error: resource Pod/test-hook/local-test-hook-test-connection not ready. status: Failed, message: pod local-test-hook-test-connection failed
   ```

   Only the failed test's Pod stays, with the status `Error`. The ConfigMap's test succeeded, and when a test fails, Helm still applies `hook-succeeded` to the tests that passed before it.
   The Pod's log shows the reason:

   ```bash
   kubectl -n test-hook logs local-test-hook-test-connection
   ```

   ```text
   curl: (6) Could not resolve host: inexistent
   ```

   The release still stores the script as it rendered: `helm -n test-hook get hooks local-test-hook` prints both test objects, with `curl http://inexistent:80` in the ConfigMap.

   Set the `curl` line back to `curl http://{{ include "test-hook.fullname" . }}:{{ .Values.service.port }}`, then upgrade and run the tests again. Both succeed, and `before-hook-creation` removed the failed Pod before the run.

7. **Turn the tests off:**

   ```bash
   helm -n test-hook upgrade local-test-hook test-hook --set tests.enabled=false
   helm -n test-hook test local-test-hook
   ```

   The release has no test hooks now, so `helm test` runs nothing, prints `TEST SUITE: None`, and exits with code 0.

   Delete the namespace when you're done:

   ```bash
   kubectl delete namespace test-hook
   ```

## Conclusion

In this exercise, we moved the test objects' settings into `values.yaml`, rendered the test objects only when `tests.enabled` is true, and made their delete policy a value, so that a successful run deletes them and a failed run keeps the Pod and its log.
