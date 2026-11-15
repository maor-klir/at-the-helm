# Exploring Helm repositories

## Overview

In this exercise, we will dive into working with Helm charts and repositories using the Helm CLI. The goal here is to familiarize ourselves with adding and managing repositories, as well as searching for specific charts.
Here's a quick summary of the main steps:

1. Identify and add the Bitnami repository using the Helm CLI `helm repo` commands.
2. Update the repository to fetch the latest chart information.
3. Search for a specific chart, like WordPress, in your added repositories.
4. Explore the metadata of the chart with the `helm show` command.
5. Add another repository, such as the Prometheus community, and verify the added repositories.
6. Perform a search for charts in the newly added repository.

## Step-by-step guide

1. **Add the Bitnami repository:**

   Open your terminal and run the command to add the Bitnami Helm repository:

   ```bash
   helm repo add bitnami https://charts.bitnami.com/bitnami
   ```

2. **Update the repository:**

   To update your local cache with the latest charts, run:

   ```bash
   helm repo update
   ```

3. **Search for the WordPress chart:**

   Execute the following command to find WordPress in your added repositories:

   ```bash
   helm search repo wordpress
   ```

4. **Show the chart metadata:**

   Use this command to display the metadata for the Bitnami WordPress chart:

   ```bash
   helm show chart bitnami/wordpress --version 23.1.20
   ```

   Without `--version`, Helm shows the latest chart (34.x). 23.1.20 is the version the following exercises install.

5. **Add another repository (Prometheus Community):**

   First, copy the installation command from the Prometheus community repository and run it in your terminal:

   ```bash
   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
   ```

6. **List your added repositories:**

   Verify that both repositories are added with:

   ```bash
   helm repo list
   ```

7. **Search for charts in the Prometheus repository:**

   Now, you can look for Prometheus charts like this:

   ```bash
   helm search repo prometheus
   ```

## Conclusion

We've explored how to add and manage Helm repositories. We learned how to update our local cache, search for charts, and view their metadata.
