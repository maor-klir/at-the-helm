#helm #kubernetes #tests

# Chart tests

A chart test is a hook on the `test` event: an object, usually a Pod or a Job, whose container checks that a release works, and that Helm creates only when `helm test` runs.
The chart tests documentation: *"The container should exit successfully (exit 0) for a test to be considered a success. The definition must contain the helm test hook annotation: `helm.sh/hook: test`."*

Tests are hooks, so the hook annotations apply to them (see **62 - Chart hooks**): *"annotations like `helm.sh/hook-weight` and `helm.sh/hook-delete-policy` may be used with test resources."*

**The annotation makes a test, not the folder:** the documentation offers `templates/tests/` as a place for tests, *"You are welcome to nest your test suite under a `tests/` directory like `<chart-name>/templates/tests/` for more isolation."*

In a chart created with `helm create`, a Pod in `templates/tests/` without the annotation was listed under `MANIFEST:` by `helm install --dry-run`, as an object of the release, and `helm template --skip-tests` kept it.
A Pod with the annotation directly in `templates/` was listed under `HOOKS:`.

## The test chart

The results below come from one chart on a k3s cluster: `test-hook`, created with `helm create`, whose Deployment runs nginx behind a ClusterIP Service on port 80.
It's installed as the release `local-test-hook` in the namespace `test-hook`.
The release's name contains the chart's name, so the scaffold's `fullname` helper names the objects `local-test-hook`.

The chart's tests took three forms:

| Form | Test objects |
|---|---|
| the scaffold's test, `templates/tests/test-connection.yaml` | the Pod `local-test-hook-test-connection`, whose `busybox` container runs `wget local-test-hook:80` |
| a script in a ConfigMap | the ConfigMap `local-test-hook-test-files`, which holds `run.sh`, and the same Pod, which runs `run.sh` in an `alpine:3.20` container |
| configurable | the same two objects, with their settings and deletion policy in `values.yaml` |

`run.sh` installs `curl`, and requests the chart's Service, so the test fails when the Service doesn't answer.

## Running tests

`helm test` takes a release, not a chart: *"The argument this command takes is the name of a deployed release. The tests to be run are defined in the chart that was installed."*
It prints the release's name, revision, and status, then one `TEST SUITE` block per test, with its start time, end time, and phase:

```text
TEST SUITE:     local-test-hook-test-connection
Last Started:   Fri Nov 27 15:49:22 2026
Last Completed: Fri Nov 27 15:49:28 2026
Phase:          Succeeded
```

A failed test sets `Phase: Failed`, prints `Error: resource Pod/test-hook/local-test-hook-test-connection not ready. status: Failed, message: pod local-test-hook-test-connection failed`, and makes `helm test` exit with code 1.
The test Pod's status is then `Error`, and its log holds the reason, such as `wget: bad address 'inexistent:80'`.

**Tests need the release to be ready:** the documentation warns that a test run right after an install *"is likely to show a transitive failure, and you will want to re-test."*
Waiting for `kubectl rollout status` first avoids that.

**Tests run from the stored release:** a test changed in the chart's directory to request a host that doesn't exist still passed, until `helm upgrade` stored the change in a new revision.
`helm get hooks local-test-hook` prints the test objects as the release stores them.

**Every test object is a test suite:** with the ConfigMap as a `test` hook too, `helm test` printed a `TEST SUITE` block for `local-test-hook-test-files` as well.
Its phase is `Succeeded` as soon as the object exists, because Helm waits only for Pods and Jobs to complete.

**A release without tests passes:** with the test templates rendering nothing, `helm test` printed `TEST SUITE: None` and exited with code 0.

`helm test` doesn't print the chart's notes, and has no `--hide-notes` flag: passing it fails with `Error: unknown flag: --hide-notes`.

### The flags

| Flag | Purpose |
|---|---|
| `--logs` | prints each test Pod's log after the results, under a header such as `POD LOGS: local-test-hook-test-connection (wget)` |
| `--filter` | runs only the tests that match, such as `name=local-test-hook-test-connection`, or excludes them with `!name=…` |
| `--timeout` | how long Helm waits for each test, five minutes by default |

**A filter that matches nothing runs nothing, without a warning:** `--filter name=no-such-test` printed the previous run's result, with its old `Last Started` time, and `Phase: Succeeded`.

## A test script in a ConfigMap

A test whose logic is more than one command can keep it in a script, outside the Pod's manifest.
The script can't live under `templates/`, where Helm renders every file as a manifest, so it lives in `files/test-scripts/run.sh` (see **61 - Accessing files in a chart**).

A ConfigMap, itself a `test` hook, loads every file of that folder:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "test-hook.fullname" . }}-test-files
  annotations:
    "helm.sh/hook": test
    "helm.sh/hook-weight": "10"
data:
{{ tpl (.Files.Glob "files/test-scripts/*").AsConfig . | indent 2 }}
```

**`tpl` renders the script's template actions:** `.AsConfig` copies the files as they are, so `{{ .Release.Name }}` in `run.sh` stayed as written.
The chart tips and tricks guide describes the function: *"The `tpl` function allows developers to evaluate strings as templates inside a template."*
Its syntax is `{{ tpl TEMPLATE_STRING VALUES }}`.

The second argument is the context the string renders with.
`.`, the top-level object, gives the script `.Release`, `.Values`, and the chart's named templates, so `curl http://{{ include "test-hook.fullname" . }}:{{ .Values.service.port }}` rendered as `curl http://local-test-hook:80`.
Without the second argument, the render fails with `wrong number of args for tpl: want 2 got 1`.

The test Pod mounts the ConfigMap as a volume, where each key becomes a file, and runs the script from it:

```yaml
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

**`defaultMode: 0744` makes the script executable:** `kubectl explain` describes the field as *"mode bits used to set permissions on created files by default"*, and its default, `0644`, gives no execute permission.

## Ordering the test objects

The Pod needs the ConfigMap, so the ConfigMap has the lower weight: `"10"`, and `"20"` for the Pod.
Steps of 10 leave room for other tests before and between them.

**Without weights, a first run times out:** tests with equal weights run in the order of their names, and `local-test-hook-test-connection` sorts before `local-test-hook-test-files`, so Helm created the Pod first (see **62 - Chart hooks**).
The Pod waited in `ContainerCreating`, with the event `MountVolume.SetUp failed for volume "tests" : configmap "local-test-hook-test-files" not found`.

Helm waits for a test Pod before it creates the next test, so the ConfigMap never came.
With `--timeout 60s`, the run failed after a minute:

```text
Error: resource Pod/test-hook/local-test-hook-test-connection not ready. status: InProgress, message: Pod in progress
context deadline exceeded
```

The same chart passed when a ConfigMap from an earlier run still existed, so the missing weights showed only once that ConfigMap was deleted.

## Deleting the test objects

Without a `helm.sh/hook-delete-policy`, the default `before-hook-creation` keeps the test objects after a run, and deletes them just before the next run creates them again.
A passed test's Pod stays with the status `Completed`, not running, and its log stays readable with `kubectl logs` until then.

With `before-hook-creation,hook-succeeded`, a successful run deleted both the Pod and the ConfigMap.
`--logs` still printed the Pod's log, as `helm test --help` describes the flag: *"this runs after all tests are complete, but before any cleanup"*.

**A failed run keeps only the failed test:** with the script requesting a host that doesn't exist, the Pod stayed with the status `Error`, and its log showed `curl: (6) Could not resolve host: inexistent`.

The ConfigMap, whose test had passed, was deleted: according to Helm's source (`execHookWithDelayedShutdown` in `pkg/action/hooks.go`), when a test fails, Helm still applies `hook-succeeded` to the tests that passed before it.

`helm get hooks` still showed the script as it rendered, with `curl http://inexistent:80`.
On the next run, `before-hook-creation` deleted the failed Pod before Helm created a new one.

**`before-hook-creation` stays in any list of policies:** naming a policy replaces the default, and `before-hook-creation` is the only one that deletes an object left by an earlier run before the next run creates it (see **62 - Chart hooks**).

With `hook-succeeded` as the only policy, a failed run left its Pod, and the next run failed again in under a second, although the script had been fixed and the release upgraded.
Helm 4 applied the test Pod over the failed one with server-side apply: the Pod kept its creation time and its `Failed` phase, and Helm reported that phase.

After `helm upgrade --server-side=false`, the same run failed with `pods "local-test-hook-test-connection" already exists` instead.
With `before-hook-creation,hook-succeeded`, the next run passed and deleted both test objects.

## Configurable tests

A chart's tests can take their settings from `values.yaml`, like any other template:

```yaml
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

**`tests.enabled` turns the tests off:** both test templates are wrapped in `{{- if .Values.tests.enabled }}` … `{{- end }}`.
With `--set tests.enabled=false`, `helm template` rendered only the ServiceAccount, the Service, and the Deployment.

**A list of policies becomes one annotation:** the annotation takes a comma-separated string, and `join` builds it from the list:

```yaml
    "helm.sh/hook-delete-policy": {{ .Values.tests.hookDeletePolicies | default (list "before-hook-creation") | join "," }}
```

The list above rendered as `before-hook-creation,hook-succeeded`.
With `hookDeletePolicies` removed, or set to `[]`, `default` replaced it with a list holding only `before-hook-creation`, Helm's default policy.

## Verify

From `06-advanced-topics/12-customize-values-yaml`, the ConfigMap and the Pod are both `test` hooks, with the ConfigMap's weight lower, and `tests.enabled=false` leaves both out:

```bash
helm template local-test-hook test-hook --show-only templates/tests/test-files.yaml --show-only templates/tests/test-connection.yaml | grep -E '^kind|"helm.sh/hook|defaultMode|command'
helm template local-test-hook test-hook --set tests.enabled=false | grep '^kind'
```

```text
kind: ConfigMap
    "helm.sh/hook": test
    "helm.sh/hook-weight": "10"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
kind: Pod
    "helm.sh/hook": test
    "helm.sh/hook-weight": "20"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
      command: ['sh', '-c', '/tests/run.sh']
        defaultMode: 0744
kind: ServiceAccount
kind: Service
kind: Deployment
```
