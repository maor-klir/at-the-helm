#helm #plugins

# Helm plugins

A plugin adds a feature to Helm without being part of Helm itself, most often a new `helm` subcommand such as `helm diff`.
The plugins overview: *"Helm Plugins allow users to extend the core feature set of Helm, without requiring every new feature to be written in Go and added to Helm core."*

Plugins are community projects. Helm's related projects page lists some of them under "Helm Plugins", and each author adds their own: *"If you have anything you'd like to add to this list, please open an issue or pull request."*
The list is therefore neither complete nor always current, and a plugin's repository can move: `lrills/helm-unittest`, the first home of helm-unittest, is archived, and the plugin is maintained in `helm-unittest/helm-unittest`.

The results below come from Helm 4.3 on a workstation, with three plugins installed from GitHub: Helm Dashboard 2.1.4, Helm Diff 3.15.15, and helm-unittest 1.3.0.
The dashboard and Helm Diff worked against a release of Headlamp, a Kubernetes web UI, installed from its chart repository on a k3s cluster.

## Plugin types

Helm 4 defines three types of plugins, and the type is part of the plugin's `plugin.yaml`:

| Type | Adds |
|---|---|
| `cli/v1` | a `helm` subcommand, such as `helm diff` or `helm unittest` |
| `getter/v1` | a download protocol for charts and plugins, such as `secrets://` or `s3://` |
| `postrenderer/v1` | a step that changes the rendered manifests before Helm sends them to Kubernetes |

**`plugin.yaml` has an `apiVersion` from Helm 4 on:** a plugin written for Helm 3 has none, and `helm plugin list` shows it as `legacy`. The overview: *"Legacy plugins (prior to API versioning) will still be supported throughout the life of Helm 4"*.
All three plugins tested here were legacy `cli/v1` plugins.

**A plugin with several capabilities becomes several plugins:** helm-secrets is distributed for Helm 4 as `helm-secrets`, `helm-secrets-getter`, and `helm-secrets-post-renderer`. The getter's `plugin.yaml` declares `apiVersion: v1`, `type: getter/v1`, and the protocols it handles.

**A plugin runs either as a process or in a sandbox:** the subprocess runtime runs an executable with the user's permissions, and the Wasm runtime runs a `.wasm` module.
The plugins user guide: *"Subprocess runtime has as much access to your system as the user running the commands."* The Wasm runtime *"runs in a secure sandbox with only the access to your system that you explicitly approve."*

## Managing plugins

| Command | Purpose |
|---|---|
| `helm plugin install` (alias `add`) | installs a plugin from a VCS repository URL, an archive URL or path, an OCI reference, or a local directory |
| `helm plugin list` (alias `ls`) | lists the installed plugins, with their type, API version, and provenance |
| `helm plugin update` | updates a plugin installed from a VCS repository, and runs its update hook |
| `helm plugin uninstall` (aliases `rm`, `remove`) | removes a plugin, and the archive and `.prov` file stored with it |
| `helm plugin package` | packages a plugin directory into an archive |
| `helm plugin verify` | checks the signature of a plugin archive |

Plugins live in `~/.local/share/helm/plugins` (`helm env HELM_PLUGINS`). A subcommand exists only while its plugin is installed: after `helm plugin uninstall dashboard`, `helm dashboard` failed with `Error: unknown command "dashboard" for "helm"`.

**`helm plugin update` works only for VCS installs:** for helm-unittest, installed from an archive, it failed with `cannot get information about plugin source`. A newer version of such a plugin is a new install.

**A legacy plugin can run scripts at install time:** Helm Dashboard's install hook downloads the latest release's binary from GitHub, and `helm plugin update dashboard` runs it again.
Installing from Git clones the repository's default branch, so the plugin's files and its downloaded binary can come from different versions.

**Archive installs ignore `HELM_PLUGINS`:** with `HELM_PLUGINS` pointing elsewhere, an archive install still went to `~/.local/share/helm/plugins`, where `helm plugin list` didn't look. According to Helm's source, the archive installers use `helmpath.DataPath("plugins")`, which follows `HELM_DATA_HOME` instead.

## Signature verification

`helm plugin install` verifies a plugin's signature by default, which needs a signed archive: the plugin's `.tgz` with a `.prov` file next to it.
A Git repository has no signature, so installing from one fails until verification is turned off:

```text
Error: plugin source does not support verification. Use --verify=false to skip verification
```

With `--verify=false`, Helm prints `WARNING: Skipping plugin signature verification` and installs the plugin. Helm Dashboard's releases have no `.prov` file, so it installs only this way.

**Helm reads keys from a keyring file:** `--keyring` defaults to `~/.gnupg/pubring.gpg`. GnuPG 2.4 keeps keys in `pubring.kbx` or in `public-keys.d`, so after `gpg --import` that file may not exist, and the install fails with `open ~/.gnupg/pubring.gpg: no such file or directory`.
`gpg --dearmor` turns a downloaded public key into a keyring file without importing it:

```bash
curl -sL https://github.com/databus23.gpg -o /tmp/databus23.asc
gpg --show-keys --with-fingerprint /tmp/databus23.asc
gpg --dearmor -o /tmp/databus23.gpg /tmp/databus23.asc
helm plugin install https://github.com/databus23/helm-diff/releases/latest/download/helm-diff-linux-amd64.tgz --keyring /tmp/databus23.gpg
```

```text
Verifying plugin signature...
Signed by: Fabian Ruff (helm-diff release key) <fabian@progra.de>
Using Key With Fingerprint: C5645EF47482257A1F806D2BEA17A2A206AFF8CD
Plugin Hash Verified: sha256:504e99410611daa70702362e1b10dc74929df8a912cb3f6b5d21d1ee9d0cb7d9
Installed plugin: diff
```

A verified install is only as trustworthy as the key. Helm Diff's README publishes the fingerprint to compare with `gpg --show-keys`; helm-unittest publishes its key in its repository, and no fingerprint in its README or release notes.

**`PROVENANCE` can show `unknown` for a verified plugin:** according to Helm's source, `helm plugin list` looks for the stored archive in a directory named after the plugin.
helm-unittest is installed in `unittest/` and shows `signed`. Helm Diff, installed from `helm-diff-linux-amd64.tgz`, is in `helm-diff-linux-amd64/` and shows `unknown`, like the unsigned dashboard in `helm-dashboard.git/`.

## Popular plugins

| Plugin | Repository | Does |
|---|---|---|
| Helm Dashboard | `komodorio/helm-dashboard` | a web UI for releases, their revisions, resources, and values, with install, upgrade, rollback, and uninstall |
| Helm Diff | `databus23/helm-diff` | previews what `helm upgrade` or `helm rollback` would change, and compares revisions |
| helm-unittest | `helm-unittest/helm-unittest` | tests a chart's rendered templates with test suites written in YAML, without a cluster |
| helm-secrets | `jkroepke/helm-secrets` | decrypts encrypted values files during `helm install` and `helm upgrade`, with sops or with secret managers through vals |

### Helm Dashboard

`helm dashboard` starts a web server at `http://localhost:8080/` and opens it in the browser; the UI works while the command runs.
Its README: *"there is user analytics collected by the tool. You can disable this collecting with `--no-analytics` option."*

**The dashboard runs Helm 3's library, not the installed Helm:** version 2.1.4 is built with Helm 3.20, which has no server-side apply. A release it installed showed `APPLY_METHOD: client-side apply (defaulted)` in `helm get metadata`, and its Deployment had the field manager `helm-dashboard`.
Helm 4's CLI listed, diffed, and uninstalled that release like any other.

**The dashboard picks its own cluster:** according to its frontend's source, it lists every context in the kubeconfig and selects the first one alphabetically, not the kubeconfig's current context. The list of releases then starts filtered to that context's default namespace.

Its install and upgrade dialogs show the manifests from a server-side dry run before anything changes. According to its source, the upgrade dialog fills in the release's values, so an upgrade keeps them.

### Helm Diff

*"This is a Helm plugin giving you a preview of what a `helm upgrade` would change."* `helm diff upgrade` takes the arguments of `helm upgrade`, renders the chart, and prints a diff against the release's manifests, one block per changed object:

```text
headlamp, headlamp, Deployment (apps) has changed:
...
-           image: "ghcr.io/headlamp-k8s/headlamp:v0.45.0"
+           image: "ghcr.io/headlamp-k8s/headlamp:v0.46.0"
```

**The diff follows Helm 4's rules for values:** with no values passed, it kept the release's values, as `helm upgrade` does.
With `--set replicaCount=3` alone, it showed the release's own values being dropped: the ClusterRoleBinding moved from `view` to `cluster-admin`, and a Secret the values had turned off came back. With `--reuse-values --set replicaCount=3`, only the replica count changed.

`--detailed-exitcode` makes the command exit with code 2 when the upgrade would change something, and with 0 when it wouldn't.

| Command | Compares |
|---|---|
| `helm diff revision <release> 1` | revision 1 with the latest revision |
| `helm diff revision <release> 2 3` | two revisions; `3 2` gave the same output, older revision first |
| `helm diff rollback <release> 2` | the latest revision with revision 2, without rolling back |

**The diff compares with the release, not with the cluster:** after `kubectl scale` changed a Deployment's replicas, `helm diff upgrade` with the release's chart version and values showed nothing.
With `--three-way-merge`, it showed the change being undone. The README: *"`--three-way-merge` diffs against what is actually in the cluster rather than against the manifests of the last release, so changes made outside of Helm show up too."*

**What the upgrade does with that change depends on the apply method:** a release installed by the dashboard used client-side apply, and the upgrade set the replicas back, as the three-way diff showed.
A release installed with Helm 4's CLI used server-side apply, and the same upgrade failed: `Apply failed with 1 conflict: conflict with "kubectl" with subresource "scale" using apps/v1: .spec.replicas`.

`kubectl scale` had made `kubectl` the manager of `.spec.replicas`. Neither helm-diff nor `helm upgrade --dry-run=server` reported the conflict, and the history recorded the upgrade as a `failed` revision.

`--force-conflicts`, *"if set server-side apply will force changes against conflicts"*, made the next upgrade take the field back: the replicas returned to the chart's value, and `kubectl` no longer appeared among the Deployment's field managers.

### helm-unittest

By default, `helm unittest` reads test suites from the chart's `tests/` directory, in files whose names end in `_test.yaml`; `-f` takes other glob patterns, such as `-f 'my-tests/*.yaml'`.
A suite names the templates to render, and each test sets values and asserts on the output:

```yaml
suite: test hook delete policy
templates:
  - tests/test-connection.yaml
tests:
  - it: should set the delete policy to before-hook-creation when tests.hookDeletePolicies is not set
    set:
      tests:
        hookDeletePolicies: []
    asserts:
      - equal:
          path: metadata.annotations["helm.sh/hook-delete-policy"]
          value: before-hook-creation
```

`helm unittest <chart>` renders the chart with the release name `RELEASE-NAME`, and reports each assertion that fails with the expected and the actual value.
Unit tests are separate from chart tests: `templates/tests/` holds hooks that `helm test` runs in a cluster (see **64 - Chart tests**).

**`set` merges into the chart's values:** `set: tests: {}` left the default `hookDeletePolicies` in place, because an empty map removes nothing. An empty list replaced it, and so did `null`, which the values files guide describes: *"Helm will remove the key from the overridden values merge."*

**`/tests/` in `.helmignore` keeps the suites out of the archive:** without the leading slash, `tests` matches *"any file or path named"* `tests`, so Helm also dropped `templates/tests/`, and the chart lost its test Pod.
With `/tests/`, `helm package` left out only the top-level directory, and `helm unittest` still read the suites from the chart's directory.

### helm-secrets

*"helm-secrets is a Helm plugin to decrypt encrypted Helm **value files** on the fly."* It encrypts values files with sops so that they can be stored in Git, or fetches secrets from a secret manager such as AWS Secrets Manager through vals.
The README prefers its protocol handler, `helm upgrade name . -f secrets://secrets.yaml`, over wrapping the whole command with `helm secrets upgrade`.

## Verify

From `06-advanced-topics/15-helm-unittest-plugin`, with the three plugins installed:

```bash
helm plugin list
helm unittest unittest-demo
```

```text
NAME     	VERSION	TYPE  	APIVERSION	PROVENANCE	SOURCE
dashboard	2.1.4  	cli/v1	legacy    	unknown   	unknown
diff     	3.15.15	cli/v1	legacy    	unknown   	unknown
unittest 	1.3.0  	cli/v1	legacy    	signed    	unknown
...
 PASS  test deployment	unittest-demo/tests/first_test.yaml
 PASS  test hook delete policy	unittest-demo/tests/test_hook_policy_test.yaml
...
Tests:       5 passed, 5 total
```
