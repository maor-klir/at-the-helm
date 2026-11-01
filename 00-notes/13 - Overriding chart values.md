#helm #kubernetes

# Overriding chart values

Every chart ships its defaults in `values.yaml`.
At install time we can replace any of them, from the command line with `--set` or from a file with `--values` (`-f`).
Helm keeps the values we pass with the release.

## Finding the right path

The keys to override come from the chart's `values.yaml`, which `helm show values` prints for a given version (see **11 - Exploring charts and releases with the Helm CLI**).
For WordPress 23.1.20, the database credentials sit two levels deep:

```bash
helm show values bitnami/wordpress --version 23.1.20 --jsonpath '{.mariadb.auth}'
# {"database":"bitnami_wordpress","password":"","rootPassword":"","username":"bn_wordpress"}
```

**A subchart's values live under its name:** MariaDB is a dependency of the WordPress chart, and the `mariadb:` block in the parent's values goes to it.
Helm's chart documentation says *"a values file can supply values to the chart as well as to any of its dependencies."*
So the root password is `mariadb.auth.rootPassword`, and the password of the `bn_wordpress` user is `mariadb.auth.password`.

**A wrong path fails silently:** a key that no template reads changes nothing, and Helm doesn't report it.
`--set mariadb.rootPassword=…` renders without an error and leaves the generated password in place.
Chart 23.1.20 ships a `values.schema.json`, but its schema doesn't reject keys it doesn't define.

## `--set` syntax

The Using Helm guide starts with the simplest form: *"The `--set` option takes zero or more name/value pairs. At its simplest, it is used like this: `--set name=value`."*
Dots build nested maps, and commas separate pairs.
The same section of the guide covers the other forms:

| `--set` | Result in YAML |
|---|---|
| `name=value` | `name: value` |
| `a=b,c=d` | `a: b` and `c: d` |
| `outer.inner=value` | `inner: value` nested under `outer:` |
| `name={a, b, c}` | `name` as a list of `a`, `b`, and `c` |
| `servers[0].port=80` | `port: 80` on the first item of the `servers` list |
| `name=[],a=null` | an empty list, and `null` |
| `name=value1\,value2` | `name: "value1,value2"` |
| `nodeSelector."kubernetes\.io/role"=master` | the key `kubernetes.io/role` under `nodeSelector` |

**Brackets only take list indexes:** `--set service[port]=8080` fails with `error parsing index: strconv.Atoi: parsing "port": invalid syntax`, and `--set service:port:8080` fails with `key "service:port:8080" has no value`.
`--set service/port=8080` renders without an error, because the slash becomes part of a key literally named `service/port`.

**Deep structures belong in a file:** the guide warns that *"Deeply nested data structures can be difficult to express using `--set`."*

**The last value wins:** the `helm install` reference says *"The priority will be given to the last (right-most) set specified."*
Repeated `-f` files follow the same rule.
When both kinds are used, the Using Helm guide says *"If both are used, `--set` values are merged into `--values` with higher precedence."*

**`--set` has typed variants:** the `helm install` reference lists four more flags.

| Flag | Reference description |
|---|---|
| `--set-string` | *"set STRING values on the command line"* |
| `--set-literal` | *"set a literal STRING value on the command line"* |
| `--set-file` | *"set values from respective files specified via the command line"* |
| `--set-json` | *"set JSON values on the command line"* |

The synopsis says when two of them help: *"to force a string value use '--set-string'"*, and *"You can use '--set-file' to set individual values from a file when the value itself is too long for the command line or is dynamically generated."*

## Values files

The Using Helm guide describes the file form: *"`--values` (or `-f`): Specify a YAML file with overrides. This can be specified multiple times and the rightmost file will take precedence"*.
A values file has the structure of the chart's `values.yaml` but holds only the keys we change.
Every other key keeps its default.

Our WordPress file sets the image repositories, the admin user, the source of the admin password, and the replica count:

```yaml
image:
  repository: bitnamilegacy/wordpress
mariadb:
  image:
    repository: bitnamilegacy/mariadb

wordpressUsername: maor
existingSecret: custom-wp-credentials
replicaCount: 3
```

```bash
helm -n wordpress install local-wp bitnami/wordpress --version 23.1.20 --values custom-values.yaml
```

**A file can name a Secret instead of holding a password:** the WordPress chart's `values.yaml` documents `existingSecret` with *"NOTE: Must contain key `wordpress-password`"* and *"NOTE: When it's set, the `wordpressPassword` parameter is ignored"*.

The rendered Deployment then reads `WORDPRESS_PASSWORD` from `custom-wp-credentials`, key `wordpress-password`, and the chart no longer renders its own `local-wp-wordpress` Secret.
The file holds only the Secret's name, so it can be committed.

**The Secret has to exist before the install, and the namespace before the Secret:** `read -rs` keeps the password out of the shell history.

```bash
kubectl create namespace wordpress
read -rs WP_PW
kubectl -n wordpress create secret generic custom-wp-credentials --from-literal=wordpress-password="$WP_PW"
unset WP_PW
```

We named it `custom-wp-credentials`, without the release's `local-wp-` prefix, so it isn't mistaken for an object the release created.

## Where the values are stored

The Using Helm guide: *"Overrides specified with `--set` are persisted in a Secret. Values that have been `--set` can be viewed for a given release with `helm get values <release-name>`."*

That Secret is the release record (see **01 - The role of Helm in Kubernetes**).
`helm get values` prints what we supplied under `USER-SUPPLIED VALUES:` (see **11 - Exploring charts and releases with the Helm CLI**).

## Set values replace generated ones

With `rootPassword` and `password` left empty, the WordPress chart generates random passwords at every install.
Setting both makes every install render the same Secret:

```bash
helm -n wordpress install local-wp bitnami/wordpress --version 23.1.20 --create-namespace \
  --values ./wp-repo-overrides.yaml \
  --set mariadb.auth.rootPassword=myAwesomePassword \
  --set mariadb.auth.password=myUserPassword
```

`helm template` with the same flags shows the `local-wp-mariadb` Secret holding exactly `myAwesomePassword` and `myUserPassword`.
A reinstall on a retained MariaDB volume then sends the passwords that the database's data expects, which avoids the failure in **12 - Uninstalling releases and persistent data.**

## Sensitive values

**A password on the command line leaves copies:** the shell saves the command line in its history.
Helm saves the value in the release record, where `helm get values` prints it in plain text to anyone who can read Secrets in the namespace.

**Variables and existing Secrets reduce the copies:** a variable keeps the password out of the history, e.g. `--set mariadb.auth.rootPassword="$MARIADB_ROOT_PASSWORD"`, though Helm still stores the value.

The MariaDB chart's `auth.existingSecret`, `mariadb.auth.existingSecret` from the WordPress chart, reads the passwords from a Secret we create ourselves.
Its README: *"Use existing secret for password details (`auth.rootPassword`, `auth.password`, `auth.replicationPassword` will be ignored and picked up from this secret)."*

A values file with real passwords in it must stay out of the repository, since the repository is public.

## Verify

Only the full path reaches the Secret; the wrong key renders without an error and leaves the value out:

```bash
helm -n wordpress template local-wp bitnami/wordpress --version 23.1.20 \
  --set mariadb.auth.rootPassword=myAwesomePassword | grep -c 'bXlBd2Vzb21lUGFzc3dvcmQ='   # 1
helm -n wordpress template local-wp bitnami/wordpress --version 23.1.20 \
  --set mariadb.rootPassword=myAwesomePassword | grep -c 'bXlBd2Vzb21lUGFzc3dvcmQ='        # 0
```

`bXlBd2Vzb21lUGFzc3dvcmQ=` is `myAwesomePassword` in base64, the form Secrets store.

After the install with both `--set` flags, the Secret holds the values we set, and the release lists them as user-supplied:

```bash
kubectl -n wordpress get secret local-wp-mariadb -o jsonpath='{.data.mariadb-password}' | base64 -d; echo   # myUserPassword
helm -n wordpress get values local-wp   # mariadb.auth.password and rootPassword under USER-SUPPLIED VALUES:
```

After `helm -n wordpress uninstall local-wp` and the same install again, the MariaDB PVC keeps its PV, and both Pods start without restarts:

```bash
kubectl -n wordpress get pvc data-local-wp-mariadb-0 -o jsonpath='{.spec.volumeName}{"\n"}'   # the same PV as before
kubectl -n wordpress get pods                                             # 1/1, 0 restarts
kubectl -n wordpress logs local-wp-mariadb-0 | grep -c 'Access denied'   # 0
```

With the values file and the existing Secret, the Deployment takes its password from our Secret, and the release lists the file's keys:

```bash
helm -n wordpress template local-wp bitnami/wordpress --version 23.1.20 --values custom-values.yaml \
  | grep -A4 'name: WORDPRESS_PASSWORD$'   # secretKeyRef: custom-wp-credentials, key wordpress-password
helm -n wordpress get values local-wp      # existingSecret, replicaCount: 3, wordpressUsername: maor
kubectl -n wordpress get pods -o wide      # three WordPress Pods, all on the node that holds the volume
```
