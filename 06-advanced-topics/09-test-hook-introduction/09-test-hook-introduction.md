# Introducing chart tests

## Overview

In this exercise, we'll install a chart created with `helm create`, run its built-in test against the release with `helm test`, and see that a change to a test takes effect only after an upgrade.
Here's a quick summary of the main steps:

1. Create the `test-hook` chart, and look at its test.
2. Install the chart, and run the test.
3. Try the options of `helm test`.
4. Break the test, and see when the change takes effect.
5. Fix the test with another upgrade.

## Step-by-step guide

The chart in `test-hook/` is the end state of this exercise: `helm create` output, unchanged. To follow the steps, run them in an empty directory.
The release is `local-test-hook` in the namespace `test-hook`.

1. **Create the chart:**

   ```bash
   helm create test-hook
   ```

   `values.yaml` sets `service.type: ClusterIP`, and the Deployment runs nginx. The scaffold also creates `templates/tests/test-connection.yaml`, a Pod whose only container runs `wget` against the chart's Service:

   ```yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: "{{ include "test-hook.fullname" . }}-test-connection"
     labels:
       {{- include "test-hook.labels" . | nindent 4 }}
     annotations:
       "helm.sh/hook": test
   spec:
     containers:
       - name: wget
         image: busybox
         command: ['wget']
         args: ['{{ include "test-hook.fullname" . }}:{{ .Values.service.port }}']
     restartPolicy: Never
   ```

   The `test` hook makes the Pod a test. The chart tests documentation describes the rule: *"The container should exit successfully (exit 0) for a test to be considered a success. The definition must contain the helm test hook annotation: `helm.sh/hook: test`."*

2. **Install the chart, and run the test:**

   Tests run against a release, not against a chart directory:

   ```bash
   helm -n test-hook install local-test-hook test-hook --create-namespace
   kubectl -n test-hook rollout status deployment/local-test-hook
   helm -n test-hook test local-test-hook
   ```

   ```text
   NAME: local-test-hook
   LAST DEPLOYED: Fri Nov 27 15:49:16 2026
   NAMESPACE: test-hook
   STATUS: deployed
   REVISION: 1
   DESCRIPTION: Install complete
   TEST SUITE:     local-test-hook-test-connection
   Last Started:   Fri Nov 27 15:49:22 2026
   Last Completed: Fri Nov 27 15:49:28 2026
   Phase:          Succeeded
   ```

   The release's name contains the chart's name, so the scaffold's `fullname` helper names the objects just `local-test-hook`, and the test `local-test-hook-test-connection`.
   Waiting for the rollout first matters: the documentation warns that a test run right after an install *"is likely to show a transitive failure"*.

   The test has no `helm.sh/hook-delete-policy`, so the default, `before-hook-creation`, keeps its Pod until the next run:

   ```bash
   kubectl -n test-hook logs local-test-hook-test-connection
   ```

   ```text
   Connecting to local-test-hook:80 (10.43.85.100:80)
   saving to 'index.html'
   index.html           100% |********************************|   612  0:00:00 ETA
   'index.html' saved
   ```

3. **Try the options:**

   `helm test --help` lists three flags of its own:

   | Flag | Purpose |
   |---|---|
   | `--logs` | prints each test Pod's log after the results, under `POD LOGS: local-test-hook-test-connection (wget)` |
   | `--filter` | runs only the tests that match, such as `--filter name=local-test-hook-test-connection` |
   | `--timeout` | how long to wait for each test, five minutes by default |

   **A filter that matches nothing runs nothing, without a warning:** `--filter name=no-such-test` printed the previous run's result, with its old `Last Started` time, and `Phase: Succeeded`.

   Helm 4's `helm test` never prints the chart's notes, so Helm 3's `--hide-notes` is gone: passing it fails with `Error: unknown flag: --hide-notes`.

4. **Break the test:**

   In `templates/tests/test-connection.yaml`, point `wget` at a host that doesn't exist:

   ```yaml
         args: ['inexistent:{{ .Values.service.port }}']
   ```

   Run `helm -n test-hook test local-test-hook` again: the test still succeeds. Tests run from the release's stored templates, so a change in the chart's directory needs an upgrade, like any other template:

   ```bash
   helm -n test-hook upgrade local-test-hook test-hook
   helm -n test-hook test local-test-hook
   ```

   ```text
   TEST SUITE:     local-test-hook-test-connection
   Last Started:   Fri Nov 27 15:50:02 2026
   Last Completed: Fri Nov 27 15:50:06 2026
   Phase:          Failed
   Error: resource Pod/test-hook/local-test-hook-test-connection not ready. status: Failed, message: pod local-test-hook-test-connection failed
   ```

   `helm test` exits with code 1, and the Pod's status is `Error`. Its log explains why:

   ```text
   wget: bad address 'inexistent:80'
   ```

5. **Fix the test with another upgrade:**

   Set `args` back to `'{{ include "test-hook.fullname" . }}:{{ .Values.service.port }}'`, and upgrade again. The release moves forward to revision 3, and the test succeeds again; `helm rollback local-test-hook 1` would have reached the same state as a new revision 4.

   Delete the namespace when you're done:

   ```bash
   kubectl delete namespace test-hook
   ```

## Conclusion

In this exercise, we ran the scaffold's test against a release with `helm test`, read its Pod's log, and saw that a changed test takes effect only after an upgrade.
Exercise 10 moves the test's logic into a script of its own.
