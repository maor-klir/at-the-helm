#helm #kubernetes

# From Compose to a Helm chart

This repository is about Helm, and config-store's `compose.yaml` matters here only as a contrast.
Compose runs the application and its database on one machine during development; a Helm chart describes the same two services as Kubernetes objects.
The `config-store` chart, in its final form in `05-chart-dependencies-subcharts/07-integrate-postgresql/subcharts/config-store`, is the example throughout.

What the application itself expects at startup is in **41 - The config-store application**.

## The mapping

| `compose.yaml` | Kubernetes object or Helm feature |
|---|---|
| `build` with `target: development` | none: Kubernetes runs images and never builds them; the chart takes `image.repository` and `image.tag` |
| the `app` service's container | a Deployment and its Pods |
| `ports: - 3000:80` | `containerPort: 80` and a Service; `kubectl port-forward` reaches it from the laptop |
| `environment`, filled from `.env` | the container's `env`, from `values.yaml` and a Secret |
| the host name `db` in `DB_URL` | the Service name `postgresql-db` |
| `depends_on` with `condition: service_healthy` | none: probes and restarts instead |
| the `db` service, `postgres:17.12` | a chart dependency, Bitnami `postgresql` 16.2.2, which renders a StatefulSet |
| the `postgres-data` volume | a PersistentVolumeClaim |
| `networks` | the cluster's Pod network; a NetworkPolicy restricts it |
| the image's default user, root | the Pod's `securityContext`: UID 1000, a read-only root filesystem, and no capabilities (see **41 - The config-store application**) |
| `develop.watch` | none |

## Configuration and the password

Compose fills `environment` from `.env`: *"When executed without an explicit `--env-file` flag, Compose searches for an `.env` file in the project directory and loads values both for self-configuration and interpolation."*

The chart builds the same `DB_URL` from three variables, two from `values.yaml` and the password from the Secret `postgres-creds`:

```yaml
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: postgres-creds
        key: password
  - name: DB_URL
    value: postgresql://$(DB_USER):$(DB_PASSWORD)@postgresql-db:5432/$(DB_NAME)
```

The Kubernetes documentation describes the `$(…)` references: *"To set dependent environment variables, you can use $(VAR_NAME) in the `value` of `env` in the configuration file."*

**The password stays out of the chart:** the chart's README creates the Secret before the install, from a separate `.env` file with the keys `password` and `postgres-password`: `kubectl create secret generic postgres-creds --from-env-file=.env`.
That file is not the application's Compose `.env`, whose keys are `DB_USER`, `DB_PASSWORD`, and `DB_NAME`.

**The `.env` belongs outside the chart's directory:** the scaffold's `.helmignore` doesn't list it, so Helm would load it with the chart's files, into a packaged archive and into the release record (see **22 - Helm chart structure**).

## Names on the network

Compose resolves service names: *"Each container for a service joins the default network and is both reachable by other containers on that network, and discoverable by its service name."*
Kubernetes resolves Service names, in the form *"`my-svc.my-namespace.svc.cluster-domain.example`"*, and a Pod in the same namespace can use the short name.

The chart fixes the PostgreSQL Service's name with `fullnameOverride: postgresql-db`, so `DB_URL` doesn't change with the release name.

## Startup order

Compose can hold the application back until the database is healthy. Helm has no such option for ordinary objects: it sorts them by kind.
The Using Helm guide lists the order, *"Helm installs resources in the following order:"*, a list that puts Secret before Service, Service before Deployment, and Deployment before StatefulSet.

So the application's Deployment is created before PostgreSQL's StatefulSet, and *"Helm does not wait until all of the resources are running before it exits."*

The application's restarts and its readiness probe cover the gap (see **41 - The config-store application**).
On k3d-argocd, the application's Pod restarted three times while PostgreSQL's image was pulled and the database started, and was ready about 70 seconds after the install.

## Storage

The named volume becomes a PersistentVolumeClaim, created from the StatefulSet's claim template in the PostgreSQL chart.
As with the volume, the data outlives the workload: `helm uninstall` leaves the claim behind (see **12 - Uninstalling releases and persistent data**).

## What stays in Compose

The image build, the development stage with `nodemon`, `develop.watch`, and the `.env` file with local credentials exist only for development on one machine.
The chart starts from a pushed image and a Secret in the cluster.

## Verify

From `05-chart-dependencies-subcharts/07-integrate-postgresql`, the chart builds `DB_URL` from its values and the Secret:

```bash
helm template config-store subcharts/config-store --show-only templates/deployment.yaml | grep -A1 -E 'name: (DB_URL|DB_PASSWORD)'
```

```text
            - name: DB_PASSWORD
              valueFrom:
--
            - name: DB_URL
              value: postgresql://$(DB_USER):$(DB_PASSWORD)@postgresql-db:5432/$(DB_NAME)
```
