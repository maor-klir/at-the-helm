# Helm Upgrade: Installing a New Version of a Chart

## Overview

In this guide, we'll explore how to use the Helm Upgrade command to install a more recent version of a chart—specifically, the Bitnami WordPress chart. Before diving into the step-by-step process, I encourage you to first try implementing the solution on your own. Here’s a brief overview of the steps you’ll want to follow:

1. Update your local Helm repositories with the command `helm repo update`.
2. Search for the latest version of the Bitnami WordPress chart.
3. Use the Helm Upgrade command to set the new version.
4. Confirm that your Pods are running correctly after the upgrade.
5. Check the release history to view changes.

## Step-by-Step Guide

The release `local-wp` from exercise 09 should be at revision 2, on chart 23.1.20.

1. **Update Repositories:**

   ```bash
   helm repo update
   ```

2. **Search for Chart Versions:**

   ```bash
   helm search repo bitnami/wordpress --versions
   ```

3. **Select the New Version:**
   Pick `23.1.28`, the version exercises 11 and 12 pin.

   > **Bitnami images moved:** the list now goes up to 34.x, whose images are the rolling `bitnami/*:latest` tags. Stay on the 23.1 line: its newest release is 23.1.29, but the following exercises use `23.1.28`, whose image tags are also in `bitnamilegacy`.

   Chart versions follow Semantic Versioning, `MAJOR.MINOR.PATCH`: a patch release should only fix bugs, a minor release may add features without breaking anything, and a major release may break existing installs. Going from 23.1.20 to 23.1.28 is a patch upgrade.

4. **Run the Upgrade Command:**

   ```bash
   helm -n wordpress upgrade local-wp bitnami/wordpress --version 23.1.28 --reset-then-reuse-values
   ```

   `--reset-then-reuse-values` starts from the new chart's defaults, applies the release's current values on top, and then any `--values` or `--set` passed with the command.

   > **Don't use `--reuse-values` here:** with `--reuse-values`, Helm replaces the new chart's defaults with the old release's merged values, including chart 23.1.20's image tags. A server-side dry run of this upgrade with `--reuse-values` still renders `bitnamilegacy/wordpress:6.6.2-debian-12-r7`, while `--reset-then-reuse-values`, or no values flags at all, renders 23.1.28's `6.6.2-debian-12-r18`.

5. **Check Pod Status:**

   ```bash
   kubectl -n wordpress get pods --watch
   kubectl -n wordpress get deploy local-wp-wordpress -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
   ```

   New WordPress Pods roll out, and the image is now `6.6.2-debian-12-r18`. The HorizontalPodAutoscaler keeps two Pods. The MariaDB image moves from `11.4.3-debian-12-r1` to `11.4.4-debian-12-r0`, so its Pod restarts on the same volume.

6. **View Release History:**

   ```bash
   helm -n wordpress history local-wp
   ```

   Revisions 1 and 2 are `superseded`, and revision 3 is `deployed` with chart `wordpress-23.1.28`. The app version stays `6.6.2`.

## Conclusion

We’ve learned how to use the Helm Upgrade command to update the version of our Bitnami WordPress chart seamlessly. Remember, understanding semantic versioning is crucial—patch updates should be non-breaking, while major version changes could require further consideration.
