# Running the test script from a ConfigMap

## Overview

In this exercise, we'll change the test Pod so that it mounts exercise 10's ConfigMap and runs `run.sh` from it, and use hook weights so that Helm creates the ConfigMap before the Pod.
Here's a quick summary of the main steps:

1. Give the ConfigMap the chart's labels and a hook weight.
2. Change the test Pod to run `/tests/run.sh` from the mounted ConfigMap.
3. Upgrade the release, and run the tests.
4. See what happens without the weights.

## Step-by-step guide

Run the commands from this folder. The chart in `test-hook/` is the end state of this exercise, and continues from exercise 10's chart.
To build it yourself, copy exercise 10's `test-hook` into an empty directory, and run the steps there. The release is `local-test-hook` in the namespace `test-hook`; install it from exercise 10's chart if it isn't there.

1. **Label and weigh the ConfigMap:**

   In `templates/tests/test-files.yaml`, add the chart's labels and a weight:

   ```yaml
   metadata:
     name: {{ include "test-hook.fullname" . }}-test-files
     labels:
       {{- include "test-hook.labels" . | nindent 4 }}
     annotations:
       "helm.sh/hook": test
       "helm.sh/hook-weight": "10"
   ```

2. **Run the script in the test Pod:**

   In `templates/tests/test-connection.yaml`, give the Pod weight `"20"`, and replace the `wget` container with one that runs the script from a mounted volume:

   ```yaml
     annotations:
       "helm.sh/hook": test
       "helm.sh/hook-weight": "20"
   spec:
     containers:
       - name: alpine
         image: alpine:3.20
         command: ['sh', '-c', '/tests/run.sh']
         volumeMounts:
           - mountPath: /tests
             name: tests
     restartPolicy: Never
     volumes:
       - name: tests
         configMap:
           name: {{ include "test-hook.fullname" . }}-test-files
           defaultMode: 0744
   ```

   | Field | Purpose |
   |---|---|
   | `volumes[].configMap` | turns the ConfigMap into a volume: each key becomes a file, so `run.sh` becomes `/tests/run.sh` |
   | `defaultMode: 0744` | makes the files executable by their owner; `kubectl explain` describes it as *"mode bits used to set permissions on created files by default"*, with `0644` as the default |
   | `volumeMounts[].mountPath` | mounts the volume at `/tests` in the container; its `name` matches the volume's |
   | `"helm.sh/hook-weight"` | `"10"` for the ConfigMap and `"20"` for the Pod, so Helm creates the ConfigMap first. Steps of 10 leave room to add hooks before and between them without renumbering; a test hook without a weight gets the default, `"0"`, and runs before both. Weights are strings: Kubernetes rejects an unquoted number as an annotation value (see **62 - Chart hooks**). |

3. **Upgrade, and run the tests:**

   The test templates changed, so the release needs an upgrade first:

   ```bash
   helm -n test-hook upgrade local-test-hook test-hook
   helm -n test-hook test local-test-hook
   ```

   ```text
   TEST SUITE:     local-test-hook-test-files
   Last Started:   Fri Nov 27 16:24:32 2026
   Last Completed: Fri Nov 27 16:24:32 2026
   Phase:          Succeeded
   TEST SUITE:     local-test-hook-test-connection
   Last Started:   Fri Nov 27 16:24:33 2026
   Last Completed: Fri Nov 27 16:24:45 2026
   Phase:          Succeeded
   ```

   Helm lists both test hooks as test suites, the ConfigMap too. The ConfigMap's suite succeeds as soon as the object exists; the Pod's is the real test, and ran for 12 seconds.

   With `--logs`, the test Pod's log shows the script at work: `apk` installs `curl` and nine other packages, then `Executing curl request to local-test-hook`, and `curl` prints nginx's `Welcome to nginx!` page.

   Both objects stay after the run, as `before-hook-creation` keeps them until the next run: `kubectl -n test-hook get pods,configmaps` lists `local-test-hook-test-connection` as `Completed`, and `local-test-hook-test-files`.

4. **See what happens without the weights:**

   Remove both `helm.sh/hook-weight` lines, upgrade, and run the tests again.
   Hooks with equal weights run in the order of their names, and `local-test-hook-test-connection` comes before `local-test-hook-test-files`: Helm now creates the Pod first (see **62 - Chart hooks**).

   The test still passed, because the ConfigMap from the previous run was still there for the Pod to mount. After `kubectl -n test-hook delete configmap local-test-hook-test-files`, as on a first run, it failed:

   ```bash
   helm -n test-hook test local-test-hook --timeout 60s
   ```

   ```text
   TEST SUITE:     local-test-hook-test-connection
   Last Started:   Fri Nov 27 16:25:37 2026
   Last Completed: Fri Nov 27 16:26:37 2026
   Phase:          Failed
   Error: resource Pod/test-hook/local-test-hook-test-connection not ready. status: InProgress, message: Pod in progress
   context deadline exceeded
   ```

   The Pod waited in `ContainerCreating`, with the event `MountVolume.SetUp failed for volume "tests" : configmap "local-test-hook-test-files" not found`. Helm waits for a test Pod before it creates the next hook, so the ConfigMap never came.

   Put the weights back, and delete the namespace when you're done:

   ```bash
   kubectl delete namespace test-hook
   ```

## Conclusion

In this exercise, we mounted the test script from a ConfigMap into the test Pod, ran it with `helm test`, and saw that only the hook weights guarantee the ConfigMap exists before the Pod needs it.
Exercise 12 makes the test configurable through `values.yaml`.
