# Integrating PostgreSQL into config-store

## Overview

In this exercise, we'll remove `demo-subchart`, configure the PostgreSQL subchart's credentials, connect config-store's Deployment to the database, and install the chart on k3d-argocd.
Here's a quick summary of the main steps:

1. Remove `demo-subchart`, and update `Chart.lock`.
2. Set the PostgreSQL chart's user, database, existing Secret, and Service name in config-store's values.
3. Add the database environment variables to config-store's Deployment.
4. Create the Secret, install the chart, and test the API.
5. Uninstall the release, and delete what it leaves behind.

## Step-by-step guide

The chart in `subcharts/config-store/` is the end state of this exercise. It continues from exercise 04's chart, which exercises 05 and 06 leave unchanged.
To build it yourself, copy exercise 04's `subcharts` directory into an empty directory, and run the steps there. The commands run from this folder, which holds `subcharts/` and, from step 5 on, the `.env` file.

1. **Remove `demo-subchart`:**

   Delete `subcharts/config-store/charts/demo-subchart/`, and remove its entry from `dependencies` in `Chart.yaml`. `Chart.lock` still lists it:

   ```bash
   helm dependency build subcharts/config-store
   ```

   ```text
   Error: the lock file (Chart.lock) is out of sync with the dependencies file (Chart.yaml). Please update the dependencies with 'helm dependency update'
   ```

   `helm dependency update subcharts/config-store` downloads PostgreSQL again and writes a `Chart.lock` with only `postgresql`. Its `digest`, `sha256:fc33a07…`, is the one from exercise 02, because the dependencies are the same again.

2. **Configure the PostgreSQL chart:**

   The course reads the chart's parameters on Artifact Hub. The archive has the same table for 16.2.2 in its README, which `helm show readme subcharts/config-store/charts/postgresql-16.2.2.tgz` prints:

   | Parameter | Description in the chart's README |
   |---|---|
   | `auth.username` | *"Name for a custom user to create"* |
   | `auth.database` | *"Name for a custom database to create"* |
   | `auth.existingSecret` | *"Name of existing secret to use for PostgreSQL credentials. `auth.postgresPassword`, `auth.password`, and `auth.replicationPassword` will be ignored and picked up from this secret."* |
   | `auth.secretKeys.adminPasswordKey` | default `postgres-password` |
   | `auth.secretKeys.userPasswordKey` | default `password` |
   | `fullnameOverride` | *"String to fully override common.names.fullname template"* |

   In config-store's `values.yaml`, remove the `demo-subchart` and `global` blocks, and extend the `postgresql:` block:

   ```yaml
   postgresql:
     image:
       repository: bitnamilegacy/postgresql
     auth:
       username: config_store_user
       database: config_store_db
       existingSecret: postgres-creds
       secretKeys:
         userPasswordKey: password
     fullnameOverride: postgresql-db
   ```

   | Value | Why |
   |---|---|
   | `existingSecret: postgres-creds` | the passwords stay out of the values; the Secret needs both `password` and `postgres-password`, because the chart ignores `auth.postgresPassword` as well |
   | `userPasswordKey: password` | repeats the chart's default, so that config-store's Deployment can read the key name from the values |
   | `fullnameOverride: postgresql-db` | fixes the name of the PostgreSQL Service, which `DB_URL` needs; without it, the name depends on the release name |

   Removing `global.defaultStorageClass` matters here: k3d-argocd has only the `local-path` StorageClass, so nothing would provision a volume for a claim on `my-custom-storageclass`.

3. **Add the environment variables:**

   In `templates/deployment.yaml`, add an `env` list after `imagePullPolicy`:

   ```yaml
             env:
               - name: PORT
                 value: "{{ .Values.service.port }}"
               {{- with .Values.postgresql.auth }}
               - name: DB_USER
                 value: {{ .username }}
               - name: DB_NAME
                 value: {{ .database }}
               - name: DB_PASSWORD
                 valueFrom:
                   secretKeyRef:
                     name: {{ .existingSecret }}
                     key: {{ .secretKeys.userPasswordKey }}
               {{- end }}
               - name: DB_URL
                 value: postgresql://$(DB_USER):$(DB_PASSWORD)@{{ .Values.postgresql.fullnameOverride }}:5432/$(DB_NAME)
   ```

   `PORT` makes the application listen on 80, the container port and the probes' port; without it, it listens on 3000 (exercise 01).
   The course first writes the full `.Values.postgresql.auth.…` paths, then moves them into the `with` block. The block ends before `DB_URL`: inside it, the dot is `.Values.postgresql.auth`, and `.Values.postgresql.fullnameOverride` fails with `nil pointer evaluating interface {}.postgresql` (see **35 - The dot and with blocks**).

   `$(DB_USER)` and the other references are expanded by Kubernetes from the variables defined above them in the same list (see **42 - From Compose to a Helm chart**).

4. **Render and lint the chart:**

   ```bash
   helm lint subcharts/config-store
   helm template config-store subcharts/config-store --show-only templates/deployment.yaml | sed -n '/env:/,/ports:/p'
   ```

   ```text
             env:
               - name: PORT
                 value: "80"
               - name: DB_USER
                 value: config_store_user
               - name: DB_NAME
                 value: config_store_db
               - name: DB_PASSWORD
                 valueFrom:
                   secretKeyRef:
                     name: postgres-creds
                     key: password
               - name: DB_URL
                 value: postgresql://$(DB_USER):$(DB_PASSWORD)@postgresql-db:5432/$(DB_NAME)
             ports:
   ```

   The PostgreSQL StatefulSet reads the same Secret: `POSTGRES_PASSWORD` from the key `password`, and `POSTGRES_POSTGRES_PASSWORD` from `postgres-password`.
   The render has 10 objects, and none of them is a Secret: with `existingSecret` set, the PostgreSQL chart doesn't create its own.

5. **Create the Secret:**

   ```bash
   kubectl create namespace config-store
   printf 'password=%s\npostgres-password=%s\n' "$(openssl rand -hex 16)" "$(openssl rand -hex 16)" > .env
   kubectl -n config-store create secret generic postgres-creds --from-env-file=.env
   kubectl -n config-store describe secret postgres-creds
   ```

   ```text
   Data
   ====
   password:           32 bytes
   postgres-password:  32 bytes
   ```

   **Keep `.env` out of the chart's directory:** the course creates it inside `config-store/`, but the scaffold's `.helmignore` doesn't list `.env`. With a test `.env` there, `helm package` put `config-store/.env` into the archive, and Helm stores a chart's files in the release record too (see **22 - Helm chart structure**).
   Here, `.env` sits in this folder, next to `subcharts/`, where the repository's `.gitignore` ignores it. The chart's `.env.example` lists the two keys.

   The password becomes part of `DB_URL`, where characters such as `@`, `:`, or `/` would break the URL; `openssl rand -hex` produces only `0`–`9` and `a`–`f`.

6. **Install the chart:**

   ```bash
   helm -n config-store install config-store ./subcharts/config-store
   kubectl -n config-store get pods -w
   ```

   Helm reports `STATUS: deployed` right away. The Pods on k3d-argocd:

   | After | `config-store` | `postgresql-db-0` |
   |---|---|---|
   | 20 s | `Completed`, 1 restart | `ContainerCreating`, pulling `bitnamilegacy/postgresql` |
   | 40 s | `CrashLoopBackOff`, 2 restarts | `Running` |
   | 50 s | `CrashLoopBackOff` | `1/1 Running` |
   | 70 s | `1/1 Running`, 3 restarts | `1/1 Running` |

   The earlier containers couldn't reach the database yet: `kubectl -n config-store logs deployment/config-store --previous` shows `Unable to connect to DB` and `connect ECONNREFUSED 10.43.152.20:5432`, the PostgreSQL Service's address.
   The application then exits with code 0, which Kubernetes reports as `Completed` and restarts anyway (see **41 - The config-store application**).

   The current container's log ends with:

   ```text
   Connected to PostgreSQL.
   Database synchronized, starting server.
   Server running on port 80
   ```

   The application binds port 80 as UID 1000 with every capability dropped: on k3d-argocd, `/proc/sys/net/ipv4/ip_unprivileged_port_start` reads `0` in a Pod's network namespace.

7. **Test the API:**

   A port-forward reaches the Service from the laptop:

   ```bash
   kubectl -n config-store port-forward svc/config-store 8080:80 > /dev/null 2>&1 &
   curl localhost:8080/api/kv
   curl -X POST -H 'Content-Type: application/json' -d '{"key":"color","value":"blue"}' localhost:8080/api/kv
   curl localhost:8080/api/kv/color
   ```

   ```text
   {"data":[]}
   {"data":{"id":1,"key":"color","value":"blue","updatedAt":"2026-11-22T14:26:10.152Z","createdAt":"2026-11-22T14:26:10.152Z"}}
   {"data":{"id":1,"key":"color","value":"blue","createdAt":"2026-11-22T14:26:10.152Z","updatedAt":"2026-11-22T14:26:10.152Z"}}
   ```

   The `POST` returns 201, the `GET`s 200. Stop the port-forward with `kill %1`.

8. **Clean up:**

   ```bash
   helm -n config-store uninstall config-store
   kubectl -n config-store get all,pvc,secret
   ```

   `helm uninstall` leaves the PersistentVolumeClaim `data-postgresql-db-0`, which the StatefulSet created, and the Secret `postgres-creds`, which we created with `kubectl` (see **12 - Uninstalling releases and persistent data**).
   A reinstall would reuse the claim and its data, initialized with the old passwords, so delete both, then the namespace and the local `.env`:

   ```bash
   kubectl -n config-store delete pvc data-postgresql-db-0
   kubectl -n config-store delete secret postgres-creds
   kubectl delete namespace config-store
   rm .env
   ```

   The `local-path` provisioner deletes the PersistentVolume with its claim.

## Conclusion

In this exercise, we configured the PostgreSQL subchart through config-store's values, passed its credentials and Service name to config-store's Deployment, and installed both on k3d-argocd, where the application connected after three restarts and served the API.
This completes the chart dependencies section.
