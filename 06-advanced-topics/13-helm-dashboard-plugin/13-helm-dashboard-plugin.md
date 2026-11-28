# Using the Helm Dashboard plugin

## Overview

In this exercise, we'll install Helm Dashboard, a community plugin that adds a web UI to Helm, and use it to install, inspect, and uninstall a release of Headlamp, a Kubernetes web UI.
Here's a quick summary of the main steps:

1. Find the plugin, and look at the `helm plugin` commands.
2. Install the plugin, and manage it with `helm plugin`.
3. Start the dashboard, and select the cluster.
4. Add Headlamp's chart repository, and install the chart from the dashboard.
5. Inspect the release in the dashboard and with the Helm CLI.
6. Uninstall the release from the dashboard.

## Step-by-step guide

Run the commands from this folder. The release is `headlamp` in the namespace `headlamp`, with the values in `headlamp-values.yaml`; exercise 14 uses the same chart.
The course installs Bitnami's WordPress chart here. Its notice before this lecture recommends a chart that isn't backed by Bitnami, and suggests Headlamp.

1. **Find the plugin:**

   Plugins extend Helm with features that aren't part of Helm itself.
   The community maintains them, and Helm's related projects page lists some of them under "Helm Plugins", Helm Dashboard among them: *"GUI for Helm, visualize releases and repositories, manifest diffs"*.
   The list isn't complete: a plugin's authors add it with an issue or pull request, as the page asks, *"If you have anything you'd like to add to this list, please open an issue or pull request."*

   `komodorio/helm-dashboard` on GitHub is maintained: release 2.1.4 came out on 2026-11-20, and its last commits are from 2026-11-21.

   A plugin runs with the user's own permissions.
   The Helm 4 plugin guide: *"Subprocess runtime has as much access to your system as the user running the commands. Be sure to carefully inspect the plugin code before installing a plugin, uninstalling a plugin, or running any helm commands that could also run these plugins."*

2. **Look at the `helm plugin` commands:**

   ```bash
   helm plugin --help
   ```

   | Command | Purpose |
   |---|---|
   | `install` (alias `add`) | installs a plugin from a VCS repository URL, an archive, or a local directory |
   | `list` (alias `ls`) | lists the installed plugins |
   | `uninstall` (aliases `rm`, `remove`) | removes a plugin |
   | `update` | updates a plugin to the latest version from its source |
   | `package` | packages a plugin directory into an archive |
   | `verify` | checks the signature of a plugin at a given path |

   `helm plugin list` prints only its header, `NAME VERSION TYPE APIVERSION PROVENANCE SOURCE`, when no plugin is installed.

3. **Install the plugin:**

   Helm 4 verifies a plugin's signature before installing it, and a Git repository has no signature to verify:

   ```bash
   helm plugin install https://github.com/komodorio/helm-dashboard.git
   ```

   ```text
   Error: plugin source does not support verification. Use --verify=false to skip verification
   ```

   `--verify=false` installs it without verification, and Helm prints `WARNING: Skipping plugin signature verification`:

   ```bash
   helm plugin install https://github.com/komodorio/helm-dashboard.git --verify=false
   ```

   ```text
   Tried to autodetect latest version: 2.1.4
   Downloading and installing helm-dashboard v2.1.4 ...
   https://github.com/komodorio/helm-dashboard/releases/download/v2.1.4/helm-dashboard_2.1.4_Linux_x86_64.tar.gz

   Helm Dashboard is installed. To start it, run the following command:
   helm dashboard
   Installed plugin: dashboard
   ```

   Helm cloned the repository's default branch, then ran the plugin's install hook, a script that downloads the latest release's binary from GitHub.

   ```bash
   helm plugin list
   ```

   ```text
   NAME     	VERSION	TYPE  	APIVERSION	PROVENANCE	SOURCE
   dashboard	2.1.4  	cli/v1	legacy    	unknown   	unknown
   ```

   | Column | Here |
   |---|---|
   | `TYPE` | `cli/v1`: the plugin adds a `helm` subcommand, `helm dashboard` |
   | `APIVERSION` | `legacy`: its `plugin.yaml` has no `apiVersion`, the field Helm 4 added. The Helm 4 plugins overview: *"Legacy plugins (prior to API versioning) will still be supported throughout the life of Helm 4"* |
   | `PROVENANCE` | `unknown`: no signature was verified |

4. **Uninstall, reinstall, and update the plugin:**

   The subcommand exists only while the plugin is installed:

   ```bash
   helm plugin uninstall dashboard
   helm dashboard
   ```

   ```text
   Uninstalled plugin: dashboard
   Error: unknown command "dashboard" for "helm"
   Run 'helm --help' for usage.
   ```

   Install it again with the same `helm plugin install … --verify=false` command.
   `helm plugin update dashboard` pulls the repository and runs the install hook again, which downloads the latest binary; it ends with `Updated plugin: dashboard`.

5. **Start the dashboard:**

   ```bash
   helm dashboard --no-analytics
   ```

   The dashboard serves its UI at `http://localhost:8080/`, and opens it in the browser. Keep the terminal running: the UI talks to that process, and Ctrl+C stops it.
   At startup, the dashboard updates every chart repository Helm knows, logging `Updating repository: …` for each.

   **`--no-analytics` turns off usage tracking:** the plugin's README states, *"there is user analytics collected by the tool. You can disable this collecting with `--no-analytics` option. The collection is done via DataDog RUM and Heap Analytics."*

   **Check the selected cluster:** on the first visit, the dashboard lists every context in the kubeconfig and selects the first one alphabetically, not the kubeconfig's current context. Select `k3d-argocd` in the cluster list.
   When the context sets a default namespace, the list of installed releases starts filtered to it; clear the filter to see every release, such as `argocd`.

   The dashboard compares its version with the latest GitHub release at startup. With 2.1.4, the latest, both matched.

6. **Add Headlamp's chart repository:**

   In the repository view, add `headlamp` with the URL `https://kubernetes-sigs.github.io/headlamp/`.
   The dashboard writes it to Helm's own repository list, as `helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/` would. The repository's chart is `headlamp`, version 0.46.0.

7. **Install Headlamp from the dashboard:**

   Choose **Install** on the `headlamp` chart, set the release name `headlamp`, the namespace `headlamp`, and version 0.46.0, and paste the contents of `headlamp-values.yaml` as the values:

   ```yaml
   clusterRoleBinding:
     clusterRoleName: view
   config:
     oidc:
       secret:
         create: false
   ```

   | Value | Purpose |
   |---|---|
   | `clusterRoleBinding.clusterRoleName: view` | binds Headlamp's ServiceAccount to the read-only `view` ClusterRole instead of the chart's default, `cluster-admin` |
   | `config.oidc.secret.create: false` | skips the `oidc` Secret the chart renders by default, as there's no OIDC provider |

   Before installing, the dialog shows the manifests the release will create.
   The dashboard gets them from a server-side dry run, which creates nothing: a ServiceAccount, a ClusterRoleBinding `headlamp-admin` bound to `view`, a Service, and a Deployment running `ghcr.io/headlamp-k8s/headlamp:v0.46.0`.

   Confirm the install. The terminal equivalent is:

   ```bash
   helm -n headlamp install headlamp headlamp/headlamp --version 0.46.0 --create-namespace --values headlamp-values.yaml
   ```

8. **Inspect the release:**

   The release's page shows its resources, manifests, values, and history, and can describe each resource. Helm 4 sees the same release:

   ```bash
   helm list -A
   ```

   ```text
   NAME    	NAMESPACE	REVISION	UPDATED                                 	STATUS  	CHART          	APP VERSION
   argocd  	argocd   	1       	2026-09-05 12:27:13.741501396 +0200 CEST	deployed	argo-cd-10.2.2 	v3.4.6
   headlamp	headlamp 	1       	2026-11-28 11:31:00.486592155 +0100 CET 	deployed	headlamp-0.46.0	0.46.0
   ```

   **The dashboard installs with Helm 3's library, not with the local Helm 4:** its binary is built with Helm 3.20, which doesn't use server-side apply.
   `helm -n headlamp get metadata headlamp` shows `APPLY_METHOD: client-side apply (defaulted)`, and the Deployment's field manager is `helm-dashboard`. A `helm install` from the Helm 4 CLI uses server-side apply.

9. **Uninstall the release from the dashboard:**

   Choose **Uninstall** on the release's page. The dashboard deleted the ServiceAccount, the Service, the Deployment, and the ClusterRoleBinding `headlamp-admin`, and `helm list -A` showed only `argocd` again.
   Headlamp keeps no data in a PersistentVolumeClaim, so nothing else is left behind.

   The install created the namespace, but the uninstall doesn't delete it:

   ```bash
   kubectl delete namespace headlamp
   ```

   Stop the dashboard with Ctrl+C. Exercise 14 uses it again.

## Conclusion

In this exercise, we installed the Helm Dashboard plugin with `--verify=false`, managed it with `helm plugin`, and used the dashboard to install, inspect, and uninstall a Headlamp release that Helm 4's CLI sees like any other.
