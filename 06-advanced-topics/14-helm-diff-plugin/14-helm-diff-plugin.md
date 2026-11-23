# Helm Diff Plugin Guide

Welcome to the Helm Diff Plugin guide! In this session, we'll explore how to use the Helm Diff plugin, a powerful tool that helps visualize changes before you apply updates to your Kubernetes applications. Let's dive into the exciting world of Helm! 🚀

## Overview

Before we jump into a step-by-step guide, why not give it a shot on your own? Here’s a quick summary of what we’re going to cover:

1. Open your Helm dashboard and ensure the Helm Diff plugin is listed.
2. Install a specific version of the NGINX chart from the Bitnami repository.
3. Install the Helm Diff plugin using your terminal.
4. Use the Helm Diff command to compare changes before upgrading.
5. Explore the diff output to understand the impact of the changes.
6. Upgrade the NGINX chart and see how the revisions are reflected in the Helm dashboard.

Give these steps a try before checking the detailed guide below!

## Step-by-Step Guide

Let’s go through the process together to use the Helm Diff plugin effectively:

1. **Open Helm Dashboard:** Begin by accessing your Helm dashboard in your browser. Make sure the Helm Diff plugin is visible in the plugins list.
2. **Install NGINX Chart:** From the Bitnami repository, choose to install the NGINX chart, specifically version 18.0.0. Confirm and let it install.

   > **Bitnami images moved:** in the install dialog, add this to **User-Defined Values.** Chart 18.0.0 renders `docker.io/bitnami/nginx:1.27.0-debian-12-r0`, which is gone; the same tag is in `docker.io/bitnamilegacy`.
   > ```yaml
   > image:
   >   repository: bitnamilegacy/nginx
   > ```
   > The terminal equivalent is `helm install nginx bitnami/nginx --version 18.0.0 --set image.repository=bitnamilegacy/nginx`.

3. **Install Helm Diff Plugin:** Open a terminal window and copy the installation command for the Helm Diff plugin from its GitHub page. Paste it into your terminal and execute it.

4. **Check Installed Plugins:** Use the command `helm plugin list` to confirm that both the Helm dashboard and Helm Diff plugins are installed correctly.

5. **Run Helm Diff Command:** Begin by running `helm diff upgrade <release-name> <chart-name>`. Make sure to replace `<release-name>` with the name of your release (e.g., NGINX) and `<chart-name>` with `bitnami/nginx`.

   > **Bitnami images moved:** pin the target version and reuse the release's values, so the diff keeps the `bitnamilegacy` image:
   > ```bash
   > helm diff upgrade <release-name> bitnami/nginx --version 18.2.6 --reuse-values
   > ```
   > 18.2.6 is the newest 18.x chart without Bitnami's substituted-image check; from 18.3.0, a `bitnamilegacy` image fails unless `global.security.allowInsecureImages=true`. Without `--version`, Helm picks the latest chart (25.x).

6. **Review Changes:** Examine the output to see a colored diff, indicating what changes will occur if you proceed with the upgrade.

7. **Upgrade NGINX:** If you’re satisfied with the diff, go ahead and perform the upgrade by executing `helm upgrade <release-name> <chart-name>`.

   > **Bitnami images moved:** use the same version as the diff: `helm upgrade <release-name> bitnami/nginx --version 18.2.6 --reuse-values`.

8. **Explore Revisions:** Use `helm diff revision <release-name> <revision-number>` to review differences between various revisions of your release.

9. **Experiment with Settings:** Feel free to adjust settings, like replica counts, and observe how they impact your deployments. Utilize the `--set` flag for passing in values during a diff.

## Conclusion

Congratulations on taking the initiative to learn about the Helm Diff plugin! 🌟 Understanding the differences between Helm revisions and upgrades can significantly boost your confidence and efficiency when managing your Kubernetes applications. Keep practicing, and embrace the journey of learning and exploring Helm functionalities!
