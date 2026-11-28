# Previewing upgrades with the Helm Diff plugin

## Overview

In this exercise, we'll install the Helm Diff plugin, verifying its signature, and use it to preview each change to a Headlamp release before the dashboard applies it, then compare the release's revisions.
Here's a quick summary of the main steps:

1. Install Headlamp 0.45.0 from the dashboard.
2. Install the Helm Diff plugin, and verify its signature.
3. Preview the upgrade to the latest chart, and apply it from the dashboard.
4. Preview and apply a values change.
5. Compare the release's revisions, and preview a rollback.
6. Change the release outside Helm, and compare the two kinds of diff.

## Step-by-step guide

Run the commands from this folder. The release is `headlamp` in the namespace `headlamp`, with the values in `../13-helm-dashboard-plugin/headlamp-values.yaml`, and the chart comes from the `headlamp` repository that exercise 13 added.
The course upgrades Bitnami's nginx chart here. Headlamp's chart, as in exercise 13, goes from 0.45.0 to 0.46.0, which changes its image and its version labels.

1. **Install Headlamp 0.45.0 from the dashboard:**

   Start the dashboard with `helm dashboard --no-analytics`, and keep it running.
   Install the `headlamp` chart, version 0.45.0, as the release `headlamp` in the namespace `headlamp`, with the values from `headlamp-values.yaml`, as in exercise 13.
   The terminal equivalent is:

   ```bash
   helm -n headlamp install headlamp headlamp/headlamp --version 0.45.0 --create-namespace --values ../13-helm-dashboard-plugin/headlamp-values.yaml
   ```

2. **Install the Helm Diff plugin:**

   Helm's related projects page describes the plugin as *"Preview `helm upgrade` as a coloured diff"*. Its README: *"This is a Helm plugin giving you a preview of what a `helm upgrade` would change."*

   The README's first install command, `helm plugin install https://github.com/databus23/helm-diff`, fails in Helm 4 with `Error: plugin source does not support verification. Use --verify=false to skip verification`, like the dashboard's in exercise 13.
   Unlike the dashboard, Helm Diff publishes signed release archives, each with a `.prov` file, so Helm 4 can verify it.

   Download the maintainer's public key, and check its fingerprint against the README's, `C5645EF4 7482257A 1F806D2B EA17A2A2 06AFF8CD`:

   ```bash
   curl -sL https://github.com/databus23.gpg -o /tmp/databus23.asc
   gpg --show-keys --with-fingerprint /tmp/databus23.asc
   ```

   ```text
   pub   rsa4096 2026-06-15 [SC] [expires: 2028-06-14]
         C564 5EF4 7482 257A 1F80  6D2B EA17 A2A2 06AF F8CD
   ```

   Convert the key into a keyring file, and install the release archive with it:

   ```bash
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

   **Helm reads the key from a keyring file:** `--keyring` defaults to `~/.gnupg/pubring.gpg`, which GnuPG 2.4 no longer writes: it keeps keys in `public-keys.d` or `pubring.kbx`, so the README's `gpg --import` doesn't create it.
   Without `--keyring`, the install failed with `Error: plugin verification failed: open ~/.gnupg/pubring.gpg: no such file or directory`.
   `gpg --dearmor` writes the key in the binary format Helm reads, without importing it into GnuPG.

   `helm plugin list` now shows both plugins:

   ```text
   NAME     	VERSION	TYPE  	APIVERSION	PROVENANCE	SOURCE
   dashboard	2.1.4  	cli/v1	legacy    	unknown   	unknown
   diff     	3.15.15	cli/v1	legacy    	unknown   	unknown
   ```

   `PROVENANCE` stays `unknown` for `diff` too, although Helm verified its signature: Helm looks for the signature in a plugin directory named after the plugin, and the archive installed it in `helm-diff-linux-amd64/`, not `diff/` (see exercise 15).

3. **Look at the diff commands:**

   ```bash
   helm diff --help
   ```

   | Command | Purpose |
   |---|---|
   | `upgrade` | shows what a `helm upgrade` would change |
   | `rollback` | shows what a `helm rollback` would change |
   | `revision` | compares the manifests of two revisions of a release |
   | `release` | compares the manifests of two releases |
   | `local` | compares two local chart directories |
   | `version` | prints the plugin's version |

4. **Preview the upgrade:**

   `helm diff upgrade` takes the same arguments as `helm upgrade`. Without `--version`, it uses the chart's latest version, 0.46.0:

   ```bash
   helm -n headlamp diff upgrade headlamp headlamp/headlamp
   ```

   ```text
   headlamp, headlamp, Deployment (apps) has changed:
     # Source: headlamp/templates/deployment.yaml
   ...
     metadata:
       name: headlamp
       namespace: headlamp
       labels:
   -     helm.sh/chart: headlamp-0.45.0
   +     helm.sh/chart: headlamp-0.46.0
         app.kubernetes.io/name: headlamp
         app.kubernetes.io/instance: headlamp
   -     app.kubernetes.io/version: "0.45.0"
   +     app.kubernetes.io/version: "0.46.0"
   ...
   -           image: "ghcr.io/headlamp-k8s/headlamp:v0.45.0"
   +           image: "ghcr.io/headlamp-k8s/headlamp:v0.46.0"
   ```

   Each object that changes gets a block, with removed lines in red and added lines in green: the Deployment, and the same two labels on the Service, the ServiceAccount, and the ClusterRoleBinding `headlamp-admin`.
   The README describes how: *"It basically generates a diff between the latest deployed version of a release and a `helm template`-rendered manifest"*.

   **Without values, the diff keeps the release's values, as `helm upgrade` does:** the ClusterRoleBinding stays bound to `view`. Passing `--values ../13-helm-dashboard-plugin/headlamp-values.yaml` gave the same output.

   **The diff shows when an upgrade would drop the values:** with `--reset-values`, which goes back to the chart's defaults, the diff showed two more changes:

   ```text
   headlamp, headlamp-admin, ClusterRoleBinding (rbac.authorization.k8s.io) has changed:
   ...
     roleRef:
   -   name: view
   +   name: cluster-admin
   headlamp, oidc, Secret (v1) has been added:
   ```

   `--detailed-exitcode` makes the result usable in a script: the command exited with code 2 for the upgrade to 0.46.0, and with code 0 for `--version 0.45.0`, which changes nothing.

   Now upgrade from the dashboard: choose **Upgrade** on the release's page. The dialog shows its own diff of the change, and fills in the release's values, so the upgrade keeps them. The release moves to revision 2.

5. **Preview and apply a values change:**

   `helm diff upgrade` accepts `--set` and `--values` like `helm upgrade`. In Helm 4, an upgrade that passes values without `--reuse-values` starts again from the chart's defaults, and the diff shows it:

   ```bash
   helm -n headlamp diff upgrade headlamp headlamp/headlamp --version 0.46.0 --set replicaCount=3
   ```

   ```text
   headlamp, headlamp, Deployment (apps) has changed:
   -   replicas: 1
   +   replicas: 3
   headlamp, headlamp-admin, ClusterRoleBinding (rbac.authorization.k8s.io) has changed:
   -   name: view
   +   name: cluster-admin
   headlamp, oidc, Secret (v1) has been added:
   ```

   With `--reuse-values --set replicaCount=3`, only the replica count changed.

   In the dashboard, choose **Reconfigure**, add `replicaCount: 3` to the values, and confirm. The release moves to revision 3, and the Deployment runs three Pods.

6. **Compare the revisions:**

   `helm diff revision --help` describes two forms: *"latest REVISION with specified REVISION"* and *"REVISION1 with REVISION2"*.

   | Command | Shows |
   |---|---|
   | `helm -n headlamp diff revision headlamp 1` | revision 1 against the latest, revision 3: the chart version, the image, and the replica count |
   | `helm -n headlamp diff revision headlamp 1 3` | the same output |
   | `helm -n headlamp diff revision headlamp 1 2` | only the chart version and the image |
   | `helm -n headlamp diff revision headlamp 2 3` | only `replicas: 1` becoming `replicas: 3` |
   | `helm -n headlamp diff revision headlamp 3 2` | the same output as `2 3`: the older revision is always on the left |

   `helm -n headlamp diff rollback headlamp 2` shows what rolling back to revision 2 would change, `replicas: 3` becoming `replicas: 1`, and rolls nothing back: the release stays at revision 3.

7. **Change the release outside Helm:**

   Scale the Deployment with `kubectl`, then preview an upgrade that changes neither the chart nor the values:

   ```bash
   kubectl -n headlamp scale deployment headlamp --replicas=2
   helm -n headlamp diff upgrade headlamp headlamp/headlamp --version 0.46.0 --reuse-values
   ```

   The diff is empty: by default, Helm Diff compares the rendered chart with the manifests stored in the release, and those didn't change.
   `--three-way-merge` also compares with the objects in the cluster:

   ```bash
   helm -n headlamp diff upgrade headlamp headlamp/headlamp --version 0.46.0 --reuse-values --three-way-merge
   ```

   ```text
   headlamp, headlamp, Deployment (apps) has changed:
   ...
   -   replicas: 2
   +   replicas: 3
   ```

   The upgrade does what the three-way diff shows: `helm -n headlamp upgrade headlamp headlamp/headlamp --version 0.46.0 --reuse-values` set the replicas back to 3, as revision 4.
   The dashboard installed this release with client-side apply, and the upgrade kept that method. A release installed with Helm 4's CLI uses server-side apply, and there the same upgrade failed with a conflict over `.spec.replicas` (see **65 - Helm plugins**).

8. **Clean up:**

   ```bash
   helm -n headlamp uninstall headlamp
   kubectl delete namespace headlamp
   ```

   Helm 4 uninstalls the release that the dashboard installed, the ClusterRoleBinding `headlamp-admin` included. Stop the dashboard with Ctrl+C.

## Conclusion

In this exercise, we installed the Helm Diff plugin from a signed archive, used `helm diff upgrade` to preview a chart upgrade and a values change before the dashboard applied them, compared the release's revisions with `helm diff revision`, and used `--three-way-merge` to see a change made outside Helm.
