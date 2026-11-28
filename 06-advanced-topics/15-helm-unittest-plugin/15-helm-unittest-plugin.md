# Testing templates with the Helm Unittest plugin

## Overview

In this exercise, we'll install the Helm Unittest plugin, verifying its signature, and write unit tests in YAML that render a chart's templates and check the output, without a cluster.
Here's a quick summary of the main steps:

1. Find the plugin's current repository, and install it.
2. Create a chart, and add a first test.
3. Make the test pass, and split it into two tests.
4. Keep the tests out of the packaged chart.
5. Test the deletion policy logic from exercise 12.

## Step-by-step guide

Run the commands from this folder. The chart in `unittest-demo/` is the end state of this exercise, created by the course with Helm 3's `helm create`.
To build it yourself, run the steps in an empty directory. No step needs a cluster.

1. **Find the plugin's current repository:**

   Helm's related projects page links `helm-unittest/helm-unittest`: *"Plugin for unit testing chart locally with YAML"*.
   The plugin's first repository, `lrills/helm-unittest`, is archived on GitHub; the maintained one released 1.3.0 on 2026-11-27.
   A plugin can move, and a list of links can fall behind, so check the repository for a deprecation notice before installing.

   The plugin renders templates and checks the output, without creating anything in a cluster. Its help: *"This renders your charts locally (without tiller) and validates the rendered output with the tests defined in test suite files."*

2. **Install the plugin:**

   The README's Helm 4 command installs from Git, and needs `--verify=false`, as the dashboard did in exercise 13.
   The plugin also publishes signed archives, in an OCI registry and on GitHub, so Helm 4 can verify it with the project's public key:

   ```bash
   curl -sSL https://github.com/helm-unittest/helm-unittest/raw/refs/heads/main/public-key.asc -o /tmp/helm-unittest.asc
   gpg --show-keys --with-fingerprint /tmp/helm-unittest.asc
   gpg --dearmor -o /tmp/helm-unittest.gpg /tmp/helm-unittest.asc
   helm plugin install oci://ghcr.io/helm-unittest/helm-unittest/unittest:1.3.0 --keyring /tmp/helm-unittest.gpg
   ```

   ```text
   Verifying plugin signature...
   Signed by: helm-unittest Plugin <helmunittest@gmail.com>
   Using Key With Fingerprint: 853008CD0B0A5A2DA04FF8A5616AD47F65B54AC7
   Plugin Hash Verified: sha256:cc13dc1d4a50327f99472d9b058dda56024aa846e418358ccdf7d740fe544ed6
   ...
   Installed plugin: unittest
   ```

   The project publishes no fingerprint to compare the key with, so the key is as trustworthy as the repository it's downloaded from.
   The README's own route, `gpg --export > ~/.gnupg/pubring.gpg`, overwrites that file with every key in GnuPG; `gpg --dearmor` writes a keyring file of its own instead, as in exercise 14.

   An archive install can't be updated: `helm plugin update unittest` failed with `cannot get information about plugin source`, so a newer version means installing its archive.

   `helm plugin list` shows `signed` in the `PROVENANCE` column for `unittest`. Helm looks for the signature in the plugin directory named after the plugin, and `unittest` is installed in `unittest/`.
   The dashboard and Helm Diff are installed in `helm-dashboard.git/` and `helm-diff-linux-amd64/`, so their `PROVENANCE` shows `unknown` (`internal/plugin/signing_info.go` in Helm's source).

3. **Create a chart, and add a first test:**

   ```bash
   helm create unittest-demo
   helm unittest unittest-demo
   ```

   ```text
   ### Chart [ unittest-demo ] unittest-demo


   Charts:      1 passed, 1 total
   Test Suites: 0 passed, 0 total
   Tests:       0 passed, 0 total
   ```

   The scaffold's `templates/tests/test-connection.yaml` is a chart test, which `helm test` runs against a release (see exercise 09).
   Unit tests are a different thing: `helm unittest --help` says *"Put the test files in "tests" directory under your chart with suffix "_test.yaml""*.

   Create `unittest-demo/tests/first_test.yaml` with the README's example:

   ```yaml
   suite: test deployment
   templates:
     - deployment.yaml
   tests:
     - it: should work
       set:
         image.tag: latest
       asserts:
         - isKind:
             of: Deployment
         - matchRegex:
             path: metadata.name
             pattern: -my-chart$
         - equal:
             path: spec.template.spec.containers[0].image
             value: nginx:latest
   ```

   | Field | Purpose |
   |---|---|
   | `suite` | names the test suite in the output |
   | `templates` | the templates the suite renders, relative to `templates/` |
   | `tests[].it` | describes what one test checks |
   | `tests[].set` | values for this test only, like `--set` |
   | `tests[].asserts` | the checks on the rendered output: here, the object's kind, a regular expression for its name, and the exact value of a field |

   ```bash
   helm unittest unittest-demo
   ```

   ```text
    FAIL  test deployment	unittest-demo/tests/first_test.yaml
   	- should work

   		- asserts[1] `matchRegex` fail
   			Template:	unittest-demo/templates/deployment.yaml
   			DocumentIndex:	0
   			ValuesIndex:	0
   			Path:	metadata.name
   			Expected to match:
   				-my-chart$
   			Actual:
   				RELEASE-NAME-unittest-demo
   ```

   The test renders the chart with the release name `RELEASE-NAME`, and the Deployment's name doesn't end in `-my-chart`.

4. **Make the test pass, and split it:**

   Suppose the naming convention is the rule, and the template is what's wrong. In `templates/deployment.yaml`, add the suffix:

   ```yaml
   metadata:
     name: {{ include "unittest-demo.fullname" . }}-my-chart
   ```

   The test passes: `PASS  test deployment	unittest-demo/tests/first_test.yaml`.

   One test that checks two unrelated things hides which one failed. Split it into two, each with its own description, and set `image.tag` only where it matters:

   ```yaml
   tests:
     - it: should match the naming convention of ending in "-my-chart"
       asserts:
         - isKind:
             of: Deployment
         - matchRegex:
             path: metadata.name
             pattern: -my-chart$
     - it: should correctly use the "image.tag" property when set
       set:
         image.tag: latest
       asserts:
         - equal:
             path: spec.template.spec.containers[0].image
             value: nginx:latest
   ```

   `Tests: 2 passed, 2 total`. With `-d`, the short form of `--debugPlugin`, the plugin also logs each step, including every rendered template.
   The course's commit has a `.debug/` folder with a rendered Deployment, which the plugin's `-d` stored at the time; with 1.3.0, `-d` only logs.

5. **Keep the tests out of the packaged chart:**

   The test files don't belong in the chart's archive. The README says to add `tests` to `.helmignore`, but that pattern matches more than the folder of unit tests:

   ```text
   # Unittest files
   tests
   ```

   The `.helmignore` documentation describes such a pattern as matching *"any file or path named"* it.
   Helm also left out `templates/tests/`: `helm template unittest-demo` no longer rendered the test Pod, and a unit test of it failed with `template "unittest-demo/templates/tests/test-connection.yaml" not exists or not selected in test suite`.

   A leading `/` anchors the pattern to the chart's root, *"in the top-level directory"*, and a trailing `/` matches only directories:

   ```text
   # Unittest files
   /tests/
   ```

   Now `helm package unittest-demo` leaves out `tests/` and keeps `templates/tests/test-connection.yaml`. `helm unittest` still finds the test files, because it reads them from the chart's directory, not through Helm's chart loader.

6. **Test the deletion policy logic:**

   Exercise 12 made the test Pod's deletion policy a value with a default. In `templates/tests/test-connection.yaml`, add the same annotation:

   ```yaml
       "helm.sh/hook-delete-policy": {{ .Values.tests.hookDeletePolicies | default (list "before-hook-creation") | join "," }}
   ```

   And at the end of `values.yaml`:

   ```yaml
   tests:
     hookDeletePolicies:
       - before-hook-creation
       - hook-succeeded
   ```

   Logic with a default is what unit tests are for: each test sets the values for one case. Create `tests/test_hook_policy_test.yaml`:

   ```yaml
   suite: test hook delete policy
   templates:
     - tests/test-connection.yaml
   tests:
     - it: should create a pod resource
       asserts:
         - isKind:
             of: Pod
     - it: should set the delete policy to before-hook-creation,hook-succeeded by default
       asserts:
         - equal:
             path: metadata.annotations["helm.sh/hook-delete-policy"]
             value: before-hook-creation,hook-succeeded
     - it: should correctly set the delete policy to before-hook-creation when tests.hookDeletePolicies is not set
       set:
         tests:
           hookDeletePolicies: []
       asserts:
         - equal:
             path: metadata.annotations["helm.sh/hook-delete-policy"]
             value: before-hook-creation
   ```

   The annotation's key contains dots and a slash, so the path writes it in brackets: `metadata.annotations["helm.sh/hook-delete-policy"]`.

   **`set` merges into the chart's values:** with `set: tests: {}`, the third test failed, because an empty map removes nothing, and `hookDeletePolicies` kept its default:

   ```text
   			Expected to equal:
   				before-hook-creation
   			Actual:
   				before-hook-creation,hook-succeeded
   ```

   An empty list replaces the default, and `default` treats it as empty. `hookDeletePolicies: null` passed too: the values files guide says that with `null`, *"Helm will remove the key from the overridden values merge."*

   ```bash
   helm unittest unittest-demo
   ```

   ```text
    PASS  test deployment	unittest-demo/tests/first_test.yaml
    PASS  test hook delete policy	unittest-demo/tests/test_hook_policy_test.yaml

   Charts:      1 passed, 1 total
   Test Suites: 2 passed, 2 total
   Tests:       5 passed, 5 total
   ```

## Conclusion

In this exercise, we installed the Helm Unittest plugin from a signed archive, tested the rendered output of a chart's templates with suites under `tests/`, kept those suites out of the packaged chart with `/tests/` in `.helmignore`, and covered each case of a value with a default.
