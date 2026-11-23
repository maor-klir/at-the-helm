# Testing, building, and pushing the image

## Overview

In this exercise, we'll build config-store's production image, test it against PostgreSQL, and push it to the GitHub Container Registry, where the charts in the following sections can pull it.
Here's a quick summary of the main steps:

1. Test the API in the Compose stack.
2. Create a GitHub token, and log in to `ghcr.io`.
3. Build the production image for `linux/amd64`, and test it.
4. Push the image, make the package public, and connect it to the repository.

## Step-by-step guide

Run the commands from your clone of the `config-store` repository, created in exercise 01.

1. **Test the API:**

   Start the stack with `docker compose up --build --watch`, and send the requests from exercise 04's step 6; Postman works as well as `curl`.
   Every route has to return the status in exercise 04's table before the image is worth building. Stop the stack with `docker compose down`.

2. **Create a token:**

   On GitHub, under Settings, Developer settings, Personal access tokens, Tokens (classic), generate a new token:

   - **Note:** a name that says where it's used, such as `ghcr push: config-store (laptop)`.
   - **Expiration:** short, such as 30 days.
   - **Scopes:** `write:packages`. If GitHub also selects `repo`, deselect it; pushing an image needs only the package scope.

   GitHub's documentation for the registry is explicit about the token type: "GitHub Packages only supports authentication using a personal access token (classic)."
   The scope covers both directions: "Select the `write:packages` scope to download and upload container images and read and write their metadata."

3. **Log in to the registry:**

   In a terminal, not through Claude Code's `!` prefix, which fails with `error: cannot perform an interactive login from a non-TTY device`:

   ```bash
   docker login ghcr.io -u maor-klir
   ```

   Paste the token at the password prompt. GitHub's documentation also shows a form for scripts, `echo $CR_PAT | docker login ghcr.io -u USERNAME --password-stdin`, with the token in an environment variable.
   Without a credential helper, Docker stores the login in `~/.docker/config.json`, encoded but not encrypted.

4. **Build the image:**

   ```bash
   docker build --platform linux/amd64 -t ghcr.io/maor-klir/config-store:1.0.0 .
   ```

   | Part | Why |
   |---|---|
   | no `--target` | the build targets the last stage, `production`, and the stages it depends on; the log shows no `development` steps |
   | `--platform linux/amd64` | this laptop and all three k3d-argocd nodes are `amd64` |
   | `ghcr.io/maor-klir/config-store` | the registry host decides where `docker push` sends the image |
   | `:1.0.0` | the same version as the chart's `appVersion` |

   The course builds for `linux/amd64` and `linux/arm64` together, for viewers on either platform. Building `arm64` on this machine needs QEMU emulation, which isn't installed, and no node here needs it.

   `docker image inspect` shows `arch=amd64`, the entrypoint `["/nodejs/bin/node"]`, and the command `["src/index.js"]`. The image is 248 MB.

5. **Test the production image:**

   Start only the database, and run the image on its network:

   ```bash
   docker compose up -d db
   set -a; . ./.env; set +a
   docker run -d --name config-store-prod --network config-store_config-store-net -p 3001:80 --user 1000 --read-only --cap-drop ALL -e PORT=80 -e DB_URL="postgresql://$DB_USER:$DB_PASSWORD@db:5432/$DB_NAME" ghcr.io/maor-klir/config-store:1.0.0
   curl -X POST -H 'Content-Type: application/json' -d '{"key":"primary","value":"blue"}' localhost:3001/api/kv
   curl localhost:3001/api/kv/primary
   ```

   The `POST` returns 201, and the `GET` returns the pair: the distroless image connects and serves the API as the development stage does.
   `--user 1000 --read-only --cap-drop ALL` runs it the way the config-store chart in `05-chart-dependencies-subcharts/` will: as UID 1000, with a read-only root filesystem and no capabilities (see **41 - The config-store application**).
   Clean up with `docker rm -f config-store-prod` and `docker compose down`.

6. **Push the image:**

   ```bash
   docker push ghcr.io/maor-klir/config-store:1.0.0
   ```

   ```text
   1.0.0: digest: sha256:cdfbf6263afe6d3352d848ad78049bd6962642793d947fc7e1553c4c430a22c2 size: 856
   ```

   `docker buildx imagetools inspect ghcr.io/maor-klir/config-store:1.0.0` lists two manifests: the `linux/amd64` image, and an `unknown/unknown` one.
   The second is no image: its annotation `vnd.docker.reference.type: attestation-manifest` marks the build provenance that Docker's builder attaches by default.

7. **Make the package public:**

   "When you first publish a package, the default visibility is private.", and an anonymous pull is refused with `UNAUTHORIZED … authentication required`.
   Open `https://github.com/users/maor-klir/packages/container/config-store/settings`, and under Danger Zone, choose Change visibility, then Public, and confirm with the package name. The change can't be undone.

   In GHCR, "public packages allow anonymous access and can be pulled without authentication or signing in via the CLI." A pull with an empty Docker configuration shows it:

   ```bash
   DOCKER_CONFIG=$(mktemp -d) docker pull ghcr.io/maor-klir/config-store:1.0.0
   ```

   The cluster can now pull the image without a pull Secret.

8. **Connect the package to the repository:**

   GitHub's documentation: "When you push a container image from the command line, the image is not linked to a repository by default."
   On the package's page, `https://github.com/users/maor-klir/packages/container/package/config-store`, click Connect Repository and choose `maor-klir/config-store`; the repository and the package must have the same owner.

   The package then appears on the repository's page and shows the repository's README.
   GitHub also suggests a `LABEL org.opencontainers.image.source` line in the Dockerfile. Passed to `docker build` as `--label` instead, it reached the image's configuration but didn't link the package, so the button is the reliable way.

## Conclusion

In this exercise, we built the production image for the cluster's platform, tested it against PostgreSQL, pushed it to `ghcr.io/maor-klir/config-store:1.0.0`, made the package public, and connected it to the repository.
The charts in the following sections can deploy this image instead of the course's `lmacademy/config-store:1.0.0`.
