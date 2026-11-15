# Packaging the Helm Chart

## Overview

In this session, we're going to package our chart into a versioned chart archive: a single `.tgz` file that can be shared and installed in place of the chart directory.
Publishing that archive in a chart repository is exercise 09.

Here’s a brief overview of what you should attempt:

1. Confirm that your Helm chart renders correctly with `helm template`, passes `helm lint`, and installs.
2. Package your Helm chart using `helm package`.
3. See how the chart version names the archive, and package a second version.
4. Install the chart from the archive file.

## Step-by-Step Guide

Run the commands from this folder. The chart in `creating-charts/nginx/` is unchanged from exercise 07.
`creating-charts/nginx-0.1.0.tgz` is the archive packaged from it, the result of this exercise.

1. **Check the Chart Before Packaging:**

   ```bash
   helm template creating-charts/nginx
   helm lint creating-charts/nginx
   ```

   The chart renders a Service and a Deployment, and `helm lint` reports only `[INFO] Chart.yaml: icon is recommended`.
   Install it once to confirm the objects it creates, then uninstall it:

   ```bash
   helm -n nginx install local-nginx creating-charts/nginx --create-namespace
   kubectl -n nginx get deploy,svc,rs,pods
   helm -n nginx uninstall local-nginx
   ```

   The release creates one Deployment, one Service, one ReplicaSet, and three Pods:

   ```text
   NAME                                READY   UP-TO-DATE   AVAILABLE   AGE
   deployment.apps/local-nginx-nginx   3/3     3            3           3s

   NAME                            TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
   service/local-nginx-nginx-svc   ClusterIP   10.43.237.226   <none>        80/TCP    3s

   NAME                                          DESIRED   CURRENT   READY   AGE
   replicaset.apps/local-nginx-nginx-b86756955   3         3         3       3s
   ```

2. **Package the Chart:**

   `helm package --help` describes the command: "This command packages a chart into a versioned chart archive file. If a path is given, this will look at that path for a chart (which must contain a Chart.yaml file) and then package that directory."

   ```bash
   helm package creating-charts/nginx
   tar tzf nginx-0.1.0.tgz
   ```

   Helm writes `nginx-0.1.0.tgz` to the current folder; `-d` writes it somewhere else. The archive holds the chart's files, with the templates not rendered:

   ```text
   nginx/Chart.yaml
   nginx/values.yaml
   nginx/templates/deployment.yaml
   nginx/templates/service.yaml
   nginx/.helmignore
   ```

   `.helmignore` doesn't exclude itself, so it's packaged too.
   Helm writes the archive's `Chart.yaml` from the parsed metadata, so its fields come out in alphabetical order; the other files are copied as they are.
   The same files are in `creating-charts/nginx-0.1.0.tgz`; only their timestamps differ.

3. **Version the Archive:**

   The archive's name comes from the chart's name and version.
   The Charts documentation: "When generating a package, the `helm package` command will use the version that it finds in the `Chart.yaml` as a token in the package name."

   A new chart version gives a new archive next to the old one. Instead of editing `Chart.yaml`, `--version` sets the version for one package:

   ```bash
   helm package creating-charts/nginx --version 0.1.1
   tar xzf nginx-0.1.1.tgz -O nginx/Chart.yaml | grep '^version'
   ```

   This writes `nginx-0.1.1.tgz` with `version: 0.1.1` inside, while `creating-charts/nginx/Chart.yaml` still says `0.1.0`.
   Delete the second archive again: `rm nginx-0.1.1.tgz`.

4. **Install from the Archive:**

   The archive is all Helm needs: `helm show chart nginx-0.1.0.tgz` reads its metadata, and `helm install` takes the file in place of the directory.

   ```bash
   helm -n nginx install local-nginx nginx-0.1.0.tgz
   kubectl -n nginx get deploy,svc,rs,pods
   ```

   The release creates the same objects as the install from the directory in step 1, down to the ReplicaSet's name, `local-nginx-nginx-b86756955`: the hash in it comes from the Pod template, which is the same.
   `helm -n nginx list` shows the release's chart as `nginx-0.1.0`.

   `helm package --sign` can also sign the archive with a PGP key, writing a provenance file, `nginx-0.1.0.tgz.prov`, next to it. `helm install --verify` checks that file before installing.

5. **Clean Up:**

   ```bash
   helm -n nginx uninstall local-nginx
   kubectl delete namespace nginx
   rm nginx-0.1.0.tgz
   ```

## Conclusion

In this exercise, we packaged the chart into a versioned archive, named after the chart's name and version, and installed a release from it. The archive is a portable artifact that can be shared and installed anywhere.
