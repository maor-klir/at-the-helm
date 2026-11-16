# Setting up the Express application with Docker

## Overview

In this exercise, we'll write a minimal Express application, build it with a multi-stage Dockerfile, and run it with Compose, syncing source changes into the container.

Here's a quick summary of the main steps:

1. Write the application in `src/index.js`, and run it with `nodemon`.
2. Write a Dockerfile with a development stage and a production stage.
3. Describe the service in `compose.yaml`, with a watch rule for `src`.
4. Run it with `docker compose up --watch`, and see a change reach the container.

## Step-by-step guide

Run the commands from the `config-store` repository, `~/repositories/github/maor-klir/config-store`.

1. **Write the application:**

   Create `src/index.js`:

   ```javascript
   const express = require('express');
   const cors = require('cors');
   const bodyParser = require('body-parser');

   const port = process.env.PORT || 3000;
   const app = express();

   app.use(cors());
   app.use(bodyParser.json());

   app.get('/', (req, res) => {
     res.send('Hello world!');
   });

   app.listen(port, () => {
     console.log(`Server running on port ${port}`);
   });
   ```

   `cors()` allows requests from any origin, and `bodyParser.json()` parses JSON request bodies into `req.body`. The port comes from the `PORT` environment variable, with `3000` as the fallback.
   A route handler receives the request and the response, and `res.send` writes the response body.

   Express has the same JSON parser built in: the Express 4 API reference lists `express.json()` as "Added in: `v4.16.0`".
   It describes the function: "This is a built-in middleware function in Express. It parses incoming requests with JSON payloads and is based on body-parser."
   `app.use(express.json())` would do the same without the `body-parser` dependency; the course uses `body-parser`.

2. **Run it with `nodemon`:**

   Add a `dev` script to `package.json`:

   ```json
   "scripts": {
     "test": "echo \"Error: no test specified\" && exit 1",
     "dev": "nodemon src/index.js"
   },
   ```

   `npm pkg set scripts.dev="nodemon src/index.js"` adds it from the command line.

   ```bash
   npm run dev
   ```

   The output ends with `Server running on port 3000`. In a second terminal:

   ```bash
   curl -i localhost:3000
   ```

   The response is `Hello world!`, with an `Access-Control-Allow-Origin: *` header from `cors()`.
   Edit the message and save: `nodemon` prints `restarting due to changes...` and starts the application again. Stop it with Ctrl+C.

3. **Write the Dockerfile:**

   ```dockerfile
   FROM node:22-alpine AS development

   WORKDIR /app
   COPY package*.json .
   RUN npm ci
   COPY src src
   CMD ["npm", "run", "dev"]

   FROM node:22-alpine AS prod-dependencies

   WORKDIR /app
   COPY package*.json .
   RUN npm ci --omit=dev

   FROM gcr.io/distroless/nodejs22-debian13 AS production

   WORKDIR /app
   COPY --from=prod-dependencies /app/node_modules node_modules
   COPY src src
   CMD ["src/index.js"]
   ```

   | Stage | Base image | What it does |
   |---|---|---|
   | `development` | `node:22-alpine` | installs every dependency, `nodemon` included, and runs `npm run dev` |
   | `prod-dependencies` | `node:22-alpine` | installs only the `dependencies`, without `devDependencies` |
   | `production` | distroless Node.js 22 | copies the production `node_modules` and `src`, and runs the application |

   `npm ci` installs exactly what `package-lock.json` records. The development stage installs 133 packages, the production dependencies 106.

   **Two changes from the course's Dockerfile:**
   - `npm ci --omit=dev` replaces `--only=production`. npm 10 still accepts the old flag, but warns: ``npm warn config only Use `--omit=dev` to omit dev dependencies from the install.``
   - `gcr.io/distroless/nodejs22-debian13` replaces `gcr.io/distroless/nodejs22`.
     Both exist, but the distroless documentation lists only the names with the Debian release, "Node.js v22 (`gcr.io/distroless/nodejs22-debian13`) and its dependencies."

   The distroless image has no shell and no npm, which is why a separate stage installs the dependencies.
   Its documentation explains the `CMD`: "The entrypoint of this image is set to "node", so this image expects users to supply a path to a .js file in the CMD."
   `docker image inspect` shows the entrypoint `["/nodejs/bin/node"]`, and the image runs as user `0`, root.

4. **Check the production stage:**

   The Docker documentation on multi-stage builds: "When you build your image, you don't necessarily need to build the entire Dockerfile including every stage. You can specify a target build stage."

   ```bash
   docker build --target production -t config-store:local .
   docker run --rm -d --name config-store-local -p 3001:80 -e PORT=80 config-store:local
   curl localhost:3001
   docker stop config-store-local
   ```

   The response is `Hello world!`. "BuildKit only builds the stages that the target stage depends on.", so building `--target development` skips the other two stages.
   Exercise 05 builds and pushes this image.

5. **Describe the service in `compose.yaml`:**

   ```yaml
   services:
     app:
       build:
         context: .
         target: development
       ports:
         - 3000:80
       environment:
         - PORT=80
       develop:
         watch:
           - action: sync
             path: ./src
             target: /app/src
       networks:
         - config-store-net

   networks:
     config-store-net:
   ```

   Compose builds the `development` stage, maps port 3000 on the host to port 80 in the container, and sets `PORT=80`, so the application listens on 80.

   The watch rule copies changes from `./src` into `/app/src`.
   The Compose documentation describes the `sync` action: "If `action` is set to `sync`, Compose makes sure any changes made to files on your host automatically match with the corresponding files within the service container."
   It adds: "`sync` is ideal for frameworks that support "Hot Reload" or equivalent functionality."

   **The named network is optional:** the Compose documentation says "By default, Compose sets up a single network for your app. Each container for a service joins the default network and is both reachable by other containers on that network, and discoverable by its service name."
   That default network is already a separate bridge network for the project, not Docker's default `bridge`. `config-store-net` only gives it a fixed name, `config-store_config-store-net`.

6. **Run it with watch:**

   ```bash
   docker compose up --build --watch
   ```

   `docker-compose`, with a dash, is the retired Compose v1; Compose v2 and later is the `docker compose` plugin.
   The output shows `⦿ Watch enabled`, then `app-1 | Server running on port 80`, and `curl localhost:3000` returns `Hello world!`.

   Edit the message in `src/index.js` and save. Compose logs `⦿ Syncing service "app" after 2 changes were detected`, `nodemon` restarts the application, and `curl` returns the new message.

7. **Keep watching with the stack in the background:**

   `--watch` can't be combined with `--detach`:

   ```text
   --detach cannot be combined with --abort-on-container-exit, --abort-on-container-failure, --attach, --attach-dependencies or --watch
   ```

   Start the stack detached and run the watch on its own instead.
   The Compose documentation notes: "Watch can also be used with the dedicated `docker compose watch` command if you don't want to get the application logs mixed with the (re)build logs and filesystem sync events."

   ```bash
   docker compose up --build -d
   docker compose watch --no-up
   ```

   `--no-up` watches the running services without building and starting them again. Stopping the watch with Ctrl+C leaves the containers running; `docker compose logs -f app` shows the application's output.

   The course chose watch over a bind mount because, in its experience, file changes in a bind mount didn't always reach `nodemon`.
   On this Linux machine, a bind mount works too: `docker run -v "$PWD/src:/app/src:Z" …` restarts `nodemon` on each change.
   `:Z` relabels the directory for SELinux: "If you use SELinux, you can add the `z` or `Z` options to modify the SELinux label of the host file or directory being mounted into the container."

8. **Stop the stack:**

   ```bash
   docker compose down
   ```

   This removes the container and the `config-store_config-store-net` network.

## Conclusion

In this exercise, we wrote a minimal Express application, built it with a three-stage Dockerfile, and ran its development stage with Compose, with `sync` keeping `src` up to date in the container.
