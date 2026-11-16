#helm #kubernetes #config-store

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

## Startup without a database

The application connects to the database before it listens: it authenticates, synchronizes the tables, and only then starts the HTTP server.
When the database isn't reachable, it logs `Unable to connect to DB` and exits, with exit code `0`.

**Kubernetes restarts it anyway:** *"The `spec` of a Pod has a `restartPolicy` field with possible values Always, OnFailure, and Never. The default value is Always."*, and *"`Always`: Automatically restarts the container after any termination."*

Until PostgreSQL accepts connections, the application container exits and restarts with a growing delay; *"When a pod is failing to start repeatedly, `CrashLoopBackOff` may appear in the `Status` field of some kubectl commands."*

**The readiness probe follows the same order:** *"Readiness probes determine when a container is ready to accept traffic."*
The server answers `/` only after the database connection works, so the Pod receives traffic only from then on.

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

With the database, `docker compose up --build --watch` waits for `Container config-store-db-1 Healthy`, and `curl localhost:3000` returns `Hello world!`.
