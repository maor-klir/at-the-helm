# Exploring Default Configurations in WordPress on Kubernetes

## Overview

In this guide, we’re diving into the default configurations you encounter when deploying a WordPress website using Helm in a Kubernetes cluster.

In this exercise, you will:

1. Access the WordPress admin panel.
2. Retrieve default credentials for your WordPress installation from the created Kubernetes Secrets.
3. Log in to the WordPress admin panel using the retrieved credentials.

## Step-by-Step Guide

Here's a concise roadmap to help you get through the exercise. The release `local-wp` from exercise 03 should be installed, with its port-forward running.

1. **Access the Admin Panel:**

   Open `http://localhost:9090/wp-admin`.

2. **Find Default Credentials:**

   - Go to the WordPress chart documentation on Artifact Hub, version 23.1.20.
   - Look for the `WordPress configuration parameters`.
   - Note that the username defaults to `user`.

3. **Retrieve the Password:**

   - Inspect the Secrets in the release's namespace, and identify the one that was created by Helm when installing WordPress:

     ```bash
     kubectl -n wordpress get secret
     ```

   - Decode its password:

     ```bash
     kubectl -n wordpress get secret local-wp-wordpress -o jsonpath='{.data.wordpress-password}' | base64 -d; echo
     ```

   - `echo` adds the newline the password lacks. Without it, zsh marks the end of the output with a `%` that isn't part of the password.

4. **Log In:**

   Return to the admin panel and enter your username and the decoded password to access your dashboard.

## Conclusion

In this session, we explored how to access the WordPress admin panel and retrieve the default configurations set up within the Kubernetes cluster.
This knowledge is essential as you continue to learn about managing applications with Kubernetes.
