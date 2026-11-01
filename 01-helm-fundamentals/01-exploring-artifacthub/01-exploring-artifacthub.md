# Exploring Helm Charts with Artifact Hub

## Overview

In this guide, we're diving into Artifact Hub, an essential resource for finding various Helm charts from reputable publishers.
Our goal is to help you understand how to navigate this tool and successfully deploy applications in your Kubernetes cluster, such as WordPress.
Before jumping into the detailed steps, let’s explore what you should aim to accomplish.

In this exercise, you will learn how to use Artifact Hub to find Helm charts. Here's a quick summary of the main steps you'll want to try on your own:

1. Go to Artifact Hub and use the search box to find a specific application (like WordPress).
2. Filter the results to show only Helm charts, focusing on verified publishers.
3. Click on a Helm chart to explore its documentation and installation instructions.
4. Review the chart's templates and default values.
5. Note the chart version to install; exercise 03 installs it.

## Step-by-Step Guide

1. **Access Artifact Hub:**
   Open your web browser and navigate to [Artifact Hub](https://artifacthub.io).

2. **Search for an Application:**
   In the search bar, type the name of an application you'd like to deploy, such as "WordPress", and press enter.

3. **Filter Results:**
   On the left side, filter the results to only show Helm charts. Look for badges indicating verified publishers for more reliable charts.

4. **Select a Helm Chart:**
   Click on the desired Helm chart to view its information, including installation instructions and required prerequisites.

5. **Explore Documentation:**
   Scroll through the documentation to find details about templates, default values, and values schemas.

6. **Review Versions:**
   Note the difference between application versions (like WordPress 6.6.2) and Helm chart versions (like 23.1.20) to understand the updates and changes.

7. **Check Maintenance Activity:**
   Look for signs of activity such as recent updates and vulnerability reports to ensure the chart is well-maintained.

8. **Read the Installation Instructions:**
   The page's install instructions use the latest chart, 34.x, which pulls the rolling `bitnami/*:latest` images into the `default` namespace. Don't install from here: exercise 03 installs chart 23.1.20 into the `wordpress` namespace, with the `bitnamilegacy` image overrides.

## Conclusion

In this session, we've explored how to effectively use Artifact Hub to find Helm charts. Remember, this resource is your go-to for a variety of applications, and it’s crucial that you check the maintenance status and reliability of the charts you choose.
