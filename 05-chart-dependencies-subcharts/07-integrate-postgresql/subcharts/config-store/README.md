# config-store

A Helm chart that deploys the config-store application, with Bitnami's `postgresql` chart as a subchart for its database.

## Setup instructions

Follow these steps to deploy the chart in the `config-store` namespace.

### 1. Configure the passwords

Create a `.env` file outside the chart's directory, with the two keys from `.env.example`:

- `password` for the password of the application's database user
- `postgres-password` for the password of the `postgres` admin user

A `.env` inside the chart's directory would be packaged with the chart and stored in the release.
The application's password becomes part of its `DB_URL`, so it must not contain characters with a special meaning in a URL, such as `@`, `:`, or `/`. `openssl rand -hex 16` produces only `0`–`9` and `a`–`f`.

### 2. Create the Kubernetes Secret

Create the namespace, and a Secret from your `.env` file:

```bash
kubectl create namespace config-store
kubectl -n config-store create secret generic postgres-creds --from-env-file=path/to/.env
```

### 3. Install the chart

From the chart's directory, for a new installation:

```bash
helm -n config-store install config-store .
```

Or with a single command for both new installation and upgrades:

```bash
helm -n config-store upgrade config-store . --install
```

Follow the creation and deployment of the Pods with `kubectl -n config-store get pods --watch`. The application's Pod restarts a few times until the database Pod is up and running.

## Troubleshooting

### 1. PostgreSQL or config-store Pod stuck in `CreateContainerConfigError`

Both Pods read their passwords from the Secret `postgres-creds`, so this is probably due to a missing Secret or password key. Make sure that:

1. There is a Secret named `postgres-creds` in the namespace where the chart is deployed.
2. The Secret contains both the `password` and `postgres-password` keys.

The kubelet keeps retrying, and the Pod's events, shown by `kubectl -n config-store describe pod <pod>`, name the missing Secret or key.

### 2. config-store Pod continuously restarting

One of the most common reasons is that the database Pod isn't available yet, so the config-store Pod can't initialize. Make sure that the PostgreSQL Pod is running and ready, which can take from a few seconds to a couple of minutes after deploying the chart.

Another common reason is an incorrect configuration of the application's Deployment template. Make sure that its values are correctly configured, especially the environment variables that specify the database credentials and the connection string.

### 3. config-store not able to authenticate to the database

This can happen if the chart was installed, uninstalled, and then installed again. The database's PersistentVolumeClaim is **not** removed when the chart is uninstalled, and keeps the data initialized with the old passwords. The solution is as follows:

1. Uninstall the chart with `helm -n config-store uninstall config-store`.
2. Remove the PersistentVolumeClaim with `kubectl -n config-store delete pvc data-postgresql-db-0`. With a dynamic provisioner whose reclaim policy is `Delete`, such as k3d-argocd's `local-path`, its PersistentVolume is deleted too; otherwise, delete it manually.
3. Install the chart again.
