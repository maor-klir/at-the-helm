#helm #kubernetes

# The config-store application

This repository is about Helm.
config-store is a small key-value store, an Express application with a PostgreSQL database, written only to give the charts in the following sections a realistic workload.
Its code lives in its own repository, `maor-klir/config-store`, and the notes cover only what a chart needs to know about it, not JavaScript, Express, Sequelize, or SQL.

How its local Compose setup maps to what a chart renders is in **42 - From Compose to a Helm chart**.

## What a chart needs to know

A chart deploys two containers, the application and PostgreSQL, and has to provide what the application reads at startup:

| What | In the application | What the chart provides |
|---|---|---|
| Listening port | `PORT`, `3000` when unset | `PORT`, and the same number as the container's `containerPort` |
| Database | `DB_URL`, a URI such as `postgresql://<user>:<password>@<host>:5432/<database>` | `DB_URL`, with the password from a Secret |
| Health | `GET /` returns `Hello world!` | liveness and readiness probes on `/` |
| Tables | `sequelize.sync()` creates missing tables at startup | nothing: no separate migration step |
| Image | the Dockerfile's `production` stage: distroless Node.js 22 running `src/index.js` | `image.repository` and `image.tag` |

The development stage, with `nodemon`, exists only for Compose; a chart always runs the production image.

## The API

The application serves its key-value pairs under `/api/kv`, with results in a `data` field and errors in an `error` field:

| Request | Success | Failures |
|---|---|---|
| `GET /api/kv` | 200, every pair | 500 |
| `GET /api/kv/<key>` | 200, the pair | 404, 500 |
| `POST /api/kv` with a JSON `key` and `value` | 201, the new pair | 400 for a missing field or an existing key, 500 |
| `PUT /api/kv/<key>` with a JSON `value` | 200, the updated pair | 400, 404, 500 |
| `DELETE /api/kv/<key>` | 204, no body | 404, 500 |

**Health checks call `/`, not the API:** the chart's probes and its `helm test` Pod, which runs `wget` against the Service, all request `/`, which answers `Hello world!` without a query.
With the database stopped after startup, `/` still returns 200 while `/api/kv` returns 500 with `getaddrinfo ENOTFOUND db`, so the probes don't notice a lost database.

## Startup without a database

The application connects to the database before it listens: it authenticates, synchronizes the tables, and only then starts the HTTP server.
When the database isn't reachable, it logs `Unable to connect to DB` and exits, with exit code `0`.

**Kubernetes restarts it anyway:** *"The `spec` of a Pod has a `restartPolicy` field with possible values Always, OnFailure, and Never. The default value is Always."*, and *"`Always`: Automatically restarts the container after any termination."*

Until PostgreSQL accepts connections, the application container exits and restarts with a growing delay; *"When a pod is failing to start repeatedly, `CrashLoopBackOff` may appear in the `Status` field of some kubectl commands."*

**The readiness probe follows the same order:** *"Readiness probes determine when a container is ready to accept traffic."*
The server answers `/` only after the database connection works, so the Pod receives traffic only from then on.

## Running as the chart runs it

The image runs as root by default: its configuration has user `0`.
The `config-store` chart overrides that, and sets resources for the container:

| Chart setting | Value |
|---|---|
| `securityContext.runAsNonRoot` and `runAsUser` | `true` and `1000` |
| `securityContext.readOnlyRootFilesystem` | `true` |
| `securityContext.capabilities.drop` | `ALL` |
| `resources.requests` and `limits` | `100m` and `128Mi`, `200m` and `256Mi` |

**The image works under these settings:** run with `--user 1000 --read-only --cap-drop ALL`, it connects to PostgreSQL, binds port 80, and serves the API, at about 38 MiB of memory.
The application writes no files, so the read-only root filesystem doesn't affect it.

**Port 80 as UID 1000 depends on the runtime:** Docker sets `net.ipv4.ip_unprivileged_port_start` to `0` inside containers, while the host's value is `1024`, so an unprivileged process may bind low ports there.
On a cluster, the container runtime decides; the Kubernetes documentation on sysctls lists `net.ipv4.ip_unprivileged_port_start` among the safe sysctls a Pod may set, since Kubernetes 1.22.
On k3d-argocd, a Pod's network namespace reads `0` as well, and the chart's Pod bound port 80 as UID 1000 with every capability dropped.

## Verify

From `~/repositories/github/maor-klir/config-store`, the production image without a database:

```bash
docker build --target production -t config-store:local .
docker run --rm -e PORT=80 -e DB_URL=postgresql://user:password@127.0.0.1:5432/db config-store:local; echo "exit code: $?"
```

```text
Unable to connect to DB
ConnectionRefusedError [SequelizeConnectionRefusedError]: connect ECONNREFUSED 127.0.0.1:5432
…
exit code: 0
```

With the database, `docker compose up --build --watch` waits for `Container config-store-db-1 Healthy`, `curl localhost:3000` returns `Hello world!`, and `curl localhost:3000/api/kv` returns `{"data":[]}` on an empty table.
