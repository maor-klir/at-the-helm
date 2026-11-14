# Publishing the Chart with GitHub Pages

## Overview

In this exercise, we'll set up a GitHub repository and GitHub Pages to publish our Helm chart at a public URL.
The repository becomes a chart repository: the packaged chart, plus an `index.yaml` file that lists it.

Here’s a quick summary of what you should aim to implement:

1. Create a new public GitHub repository, `helm-charts`.
2. Enable GitHub Pages, deploying from the `main` branch.
3. Clone the repository outside of any other Git repository.
4. Add the packaged chart and generate an `index.yaml` file for it.
5. Commit and push, then check that both files are served from the GitHub Pages URL.

## Step-by-Step Guide

This exercise has no chart of its own: it publishes exercise 08's chart in a separate repository.
The commands assume that repository is `maor-klir/helm-charts`, cloned next to this one, in `~/repositories/github/maor-klir/`.

1. **Create a GitHub Repository:**

   On GitHub, create a new repository without a template:

   - Name it `helm-charts`, and give it a description such as "Repository to host Helm charts created during courses".
   - Make it **public**.
   - Add a README file and the **MIT License**, and skip `.gitignore`.

   The repository has to be public for GitHub Pages on a free account: GitHub's documentation lists Pages for public repositories on GitHub Free, and for private ones only on the paid plans.

   With the GitHub CLI, the same repository is one command: `gh repo create maor-klir/helm-charts --public --description "Repository to host Helm charts created during courses" --add-readme --license mit`.

2. **Enable GitHub Pages:**

   In the repository's **Settings**, open **Pages**.
   Under **Build and deployment**, set **Source** to **Deploy from a branch**, choose the `main` branch and the `/ (root)` folder, and click **Save**.

   GitHub's documentation describes the choice: "The source branch can be any branch in your repository, and the source folder can either be the root of the repository (`/`) on the source branch or a `/docs` folder on the source branch."

   Saving starts a deployment in the **Actions** tab: "Your GitHub Pages site will always be deployed with a GitHub Actions workflow run."
   Once it finishes, the site is live at `https://maor-klir.github.io/helm-charts/`, the project-site address `https://<owner>.github.io/<repositoryname>`, and its root page shows the README.

   > **A `gh-pages` branch instead:** Helm's chart repository guide publishes from a separate `gh-pages` branch, so the default branch can hold the charts' source code.
   > For a repository that holds only packaged charts, as this one does, serving `main` works the same.

3. **Clone the Repository:**

   Clone it next to this repository, not inside it:

   ```bash
   cd ~/repositories/github/maor-klir
   git clone git@github.com:maor-klir/helm-charts.git
   ```

   A clone inside `at-the-helm` would be a Git repository nested in another one: the outer repository would see it as an untracked folder, and `git add` would record it as an embedded repository instead of its files.

4. **Add the Packaged Chart:**

   Package exercise 08's chart straight into the clone. `-d` sets where `helm package` writes the archive:

   ```bash
   helm package at-the-helm/02-creating-own-helm-charts/08-ide-package-chart/creating-charts/nginx -d helm-charts
   ```

   Copying exercise 08's `creating-charts/nginx-0.1.0.tgz` into `helm-charts/` works as well.

5. **Generate the Index:**

   ```bash
   cd helm-charts
   helm repo index .
   cat index.yaml
   ```

   Helm's chart repository guide explains why: "A valid chart repository must have an index file."
   The index lists every chart version in the folder, with its `Chart.yaml` fields, a digest of the archive, and the URL to download it from:

   ```yaml
   apiVersion: v1
   entries:
     nginx:
     - apiVersion: v2
       appVersion: 1.27.0
       created: "2026-11-14T13:34:12.828817986+01:00"
       description: A Helm chart for deploying Nginx to Kubernetes
       digest: bc3c63fe54574d3791a12c831419bd8dba8f7b717d554517498f200b28d053df
       name: nginx
       type: application
       urls:
       - nginx-0.1.0.tgz
       version: 0.1.0
   generated: "2026-11-14T13:34:12.828550174+01:00"
   ```

   This is the index published in `maor-klir/helm-charts`; a new run gives new timestamps, and a new archive a new digest.
   Without `--url`, the download URL is relative, `nginx-0.1.0.tgz`, and Helm resolves it against the repository's URL, so the archive must be served next to `index.yaml`.
   The guide's own example passes the repository URL to get absolute URLs instead: `helm repo index . --url https://maor-klir.github.io/helm-charts` writes `https://maor-klir.github.io/helm-charts/nginx-0.1.0.tgz`.

   Run `helm repo index` again every time you add a chart version.
   It rebuilds the file from the archives in the folder: "The `helm repo index` command will completely rebuild the `index.yaml` file from scratch, including only the charts that it finds locally."

6. **Commit and Push:**

   ```bash
   git add index.yaml nginx-0.1.0.tgz
   git commit -m "feat(nginx): publish nginx chart version 0.1.0"
   git push
   ```

   The push starts another deployment in the **Actions** tab.

7. **Check the Published Files:**

   Once the deployment finishes, both files are served from the GitHub Pages URL:

   ```bash
   curl -s https://maor-klir.github.io/helm-charts/index.yaml
   curl -sI https://maor-klir.github.io/helm-charts/nginx-0.1.0.tgz | head -1
   ```

   The first command prints the index from step 5, and the second prints `HTTP/2 200` for the archive.
   Exercise 10 adds this chart repository to Helm and installs the chart from it.

   > **Other ways to publish:** Helm's guide points to the Chart Releaser Action, a GitHub Actions workflow that packages charts and updates `index.yaml` on each release.
   > It also suggests OCI registries for new repositories: "If you are considering creating a chart repository, you may want to consider using an OCI registry instead."
   > An OCI registry needs no `index.yaml`; `helm push` uploads the archive directly.

## Conclusion

In this exercise, we created a public GitHub repository, served it with GitHub Pages, and published the packaged chart in it together with an `index.yaml`, which turns the repository into a chart repository.
