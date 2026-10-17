#helm #kustomize #kubernetes

# Helm vs. Kustomize

Helm and Kustomize both produce Kubernetes manifests that differ between installations, and both are used for the same job: one application, several environments.
The two tools work differently.

Helm renders templates with values and then manages the result as a release (see **01 - The role of Helm in Kubernetes**).
Kustomize starts from plain manifests and edits them with the patches and transformers listed in a `kustomization.yaml`, and leaves applying the result to `kubectl`.
The Kustomize documentation describes its approach:

> *"Kustomize provides a solution for customizing Kubernetes resource configuration free from templates and DSLs."*

Kustomize is a standalone tool and is also built into `kubectl`: *"Since 1.14, kubectl also supports the management of Kubernetes objects using a kustomization file."*
`kubectl version --client` reports the embedded version; kubectl 1.37.1 ships Kustomize v5.8.1.

## The same change in both tools

Both examples start from an nginx Deployment with three replicas running `nginx:1.27.0`, and change it to five replicas running `nginx:1.27.1` for production.
Both pin a version tag, as the Kubernetes documentation on images recommends:

> *"You should avoid using the `:latest` tag when deploying containers in production as it is harder to track which version of the image is running and more difficult to roll back properly."*

### Helm: a template and a values file

The template marks every value that can change with an action, `{{ }}`:

```yaml
# nginx/templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app: {{ .Release.Name }}
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "nginx:{{ .Values.image.tag }}"
          ports:
            - containerPort: 80
```

The chart's `values.yaml` holds the defaults, `replicaCount: 3` and `image.tag: 1.27.0`.
Production overrides them in its own file:

```yaml
# values-prod.yaml
replicaCount: 5
image:
  tag: 1.27.1
```

Three built-in objects supply the data:

- **`.Values`:** *"Values passed into the template from the `values.yaml` file and from user-supplied files."* Nested values are read with dots, as in `.Values.image.tag`.
- **`.Release`:** *"This object describes the release itself."* `.Release.Name` is the name given to `helm install`, so two releases of this chart in one namespace create two differently named Deployments.
- **`.Chart`:** *"The contents of the `Chart.yaml` file."* `.Chart.Name` is `nginx`.

`helm template web ./nginx -f values-prod.yaml` renders:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 5
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: nginx
          image: "nginx:1.27.1"
          ports:
            - containerPort: 80
```

### Kustomize: a base and a patch

The base is the plain manifest with every value written out, plus a `kustomization.yaml` that lists it under `resources`:

```yaml
# base/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.27.0
          ports:
            - containerPort: 80
```

```yaml
# base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
```

`apiVersion` and `kind` identify the file as a Kustomization.
`kubectl kustomize` also builds a kustomization without those two lines, and the shorter examples below leave them out.

The production overlay holds only the fields that change, as a strategic merge patch, and a `kustomization.yaml` that points to the base:

```yaml
# overlays/prod/patch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 5
  template:
    spec:
      containers:
        - name: nginx
          image: nginx:1.27.1
```

```yaml
# overlays/prod/kustomization.yaml
resources:
  - ../../base
patches:
  - path: patch.yaml
```

`kubectl kustomize overlays/prod` merges the patch into the base.
Every field the patch does not mention, such as the selector, the labels, and the port, comes from the base unchanged:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 5
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - image: nginx:1.27.1
        name: nginx
        ports:
        - containerPort: 80
```

The patch finds the Deployment by kind and name, and the container by its `name`.
That is how a strategic merge patch treats lists: *"a list is either replaced or merged depending on its patch strategy."*

The Kubernetes documentation shows the `Containers` field of `PodSpec` declared with `patchStrategy:"merge" patchMergeKey:"name"`, so containers are merged by name.
A list without a patch strategy, such as `tolerations`, is replaced as a whole.

For replicas and images Kustomize also has dedicated fields.
This overlay renders output identical to the patch above:

```yaml
resources:
  - ../../base
replicas:
  - name: nginx-deployment
    count: 5
images:
  - name: nginx
    newTag: 1.27.1
```

## Why Kustomize has no templates

Kustomize leaves templates out on purpose.
Its list of eschewed features says that parameterized source material *"is no longer structured, making it unusable with any YAML processor"*, and that *"Errors in the output are disconnected from the edit that caused it."*
It concludes:

> *"kustomize is going to stick to YAML in / YAML out."*

Two properties follow from that choice.

**Every file stays a valid manifest:** a base can be applied with `kubectl apply -f` as it is, read by any YAML tool, and taken from someone else's repository.
The Kustomize overview says: *"The resources in this directory could be a fork of someone else's configuration. If so, you can easily rebase from the source material to capture improvements, because you don't modify the resources directly."*

**The output depends only on the files:** Kustomize *"supports the best practice of storing one's entire configuration in a version control system"*, and the same page rules out input at build time: *"Changing `kustomize build` configuration output as a result of additional arguments or flags to `build`, or by consulting shell environment variable values in `build` code, would frustrate that goal."*

A value that comes from outside is first written into the kustomization, for example with `kustomize edit set image nginx:$MY_NGINX_VERSION`.
`edit` belongs to the standalone `kustomize` binary; `kubectl kustomize` only builds.

Helm works the other way.
The release name, the `-f` files, and the `--set` flags all change what a chart renders, at the moment it is installed.

## What each tool can change

**A chart changes only what its templates expose:** if no template reads a value for a field, an installation cannot set that field, short of forking the chart or post-rendering its output (see **02 - Benefits and limitations of Helm**).
A Kustomize patch can set any field of any object, including objects in manifests written by someone else.

**Kustomize copies values but does not compute them:** it has no conditionals, loops, or template functions.
A patch states a final value; it cannot derive one value from another, repeat an object for each item in a list, or include an object only when a setting is on.

`replacements` *"copy the value from a resource's field into any number of specified targets."*
For optional features, Kustomize has components, kustomizations that an overlay includes or leaves out:

> *"Components come in handy when dealing with applications that support multiple optional features and you wish to enable only a subset of them in different overlays, i.e., different features for different environments or audiences."*

## Comparison

| Dimension | Helm | Kustomize |
|---|---|---|
| Purpose | package manager: charts, repositories, releases | customizes existing manifests through a kustomization file |
| Source files | templates in the Helm template language, plus values | plain manifests, plus `kustomization.yaml` |
| Input at install time | release name, `-f` files, `--set` | none; the output depends only on the files |
| What an installation can change | what the templates expose | any field of any object |
| Customization features | conditionals, loops, functions, named templates | `patches`, `namePrefix`/`nameSuffix`, `namespace`, `labels`, `commonAnnotations`, `images`, `replicas`, generators, `replacements`, components |
| Distribution | versioned chart archives in chart repositories or OCI registries | directories, including remote bases referenced by Git URL with `?ref=` |
| Dependencies | `dependencies` in `Chart.yaml`, version ranges, `Chart.lock` | `resources` entries that point to other kustomizations |
| Applying | `helm install`, `helm upgrade` | `kubectl apply -k` |
| History and rollback | revisions stored in the cluster, `helm rollback` | nothing in the cluster; the history is the version control history |
| Objects removed from the configuration | deleted by the next `helm upgrade` | left running by `kubectl apply -k` unless pruned |
| Restarting Pods when configuration changes | a checksum annotation in the Pod template | a content hash in the names of generated ConfigMaps and Secrets |
| What there is to learn | the template language, the chart structure, the release lifecycle | the kustomization fields and how patches merge |

### Kustomize fields in v5

The current fields replace several older ones, and `kubectl kustomize` warns when it finds them:

```text
# Warning: 'commonLabels' is deprecated. Please use 'labels' instead. Run 'kustomize edit fix' to update your Kustomization automatically.
# Warning: 'patchesStrategicMerge' is deprecated. Please use 'patches' instead. Run 'kustomize edit fix' to update your Kustomization automatically.
```

`patchesJson6902` and `vars` are deprecated as well: *"The `patchesJson6902` field was deprecated in v5.0.0."*
`patches` accepts both strategic merge and JSON patches, and `replacements` takes over from `vars`.

**`labels` leaves selectors alone by default:** `commonLabels` adds its labels to selectors as well: *"Labels will be added to resource selector and template fields where applicable."*
A Deployment's `spec.selector` cannot change after creation, so adding a common label to an overlay that is already deployed makes the next apply fail.
`labels` touches selectors only when `includeSelectors` is set, which *"Defaults to false."*

**A JSON patch addresses list items by position:** the same `patches` field takes RFC 6902 operations with a target.

```yaml
patches:
  - target:
      kind: Deployment
      name: nginx-deployment
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 5
      - op: add
        path: /spec/template/spec/containers/0/env
        value:
          - name: LOG_LEVEL
            value: debug
```

`containers/0` is the first container in the base, so the patch depends on the order of that list.
A strategic merge patch matches the container by name instead.

### Lifecycle

**Helm removes what a chart no longer renders:** Helm's source compares the objects of the previous revision with the new one, and `helm upgrade` deletes the objects that are no longer rendered.

**`kubectl apply -k` only creates and updates:** an object removed from the kustomization stays in the cluster.

The Kubernetes documentation recommends deleting explicitly: *"Manually deleting objects using the imperative command is the recommended approach, as it is more explicit about what is being deleted, and less likely to result in the user deleting something unintentionally"*.
Both pruning modes of `kubectl apply --prune`, allowlist-based and ApplySet-based, are alpha.

**Rollback is a version control operation:** Kustomize keeps nothing in the cluster, so returning to an earlier state means applying an earlier commit of the overlay.

### Restarting Pods when configuration changes

Changing a ConfigMap does not restart the Pods that use it; a Deployment rolls out new Pods only when its Pod template changes.

Kustomize generators handle this through names: *"Changes to the contents will change the name suffix, resulting in the creation of a new ConfigMap, which Kustomize will transform Workloads to point to."*
Changing one literal in a `configMapGenerator` renames the ConfigMap from `nginx-config-hf678c7m2b` to `nginx-config-47668c6k28`, and the Deployment's reference changes with it.

A chart gets the same effect from an annotation that holds a hash of the rendered ConfigMap, as Helm's tips and tricks show:

```yaml
kind: Deployment
spec:
  template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
```

## Using both together

**Kustomize after Helm:** a post-renderer passes Helm's rendered manifests through another tool, such as Kustomize, before Helm installs them; in Helm 4 the post-renderer is a plugin (see **02 - Benefits and limitations of Helm**).
The chart keeps its release lifecycle, and the patches reach fields the chart does not expose.

**Helm inside Kustomize:** the `helmCharts` field renders a chart with `helm template` and adds the result to the kustomization's resources.
It needs `--enable-helm`, and works with Helm 4.3.1 as the `helm` binary:

```yaml
helmCharts:
  - name: nginx
    releaseName: web
    valuesInline:
      replicaCount: 5
      image:
        tag: 1.27.1
helmGlobals:
  chartHome: charts
```

```bash
kubectl kustomize --enable-helm .
```

The Kustomize documentation limits this generator: *"The helm chart inflation generator in kustomize is intended to be a limited subset of helm features to help with getting started with kustomize, and we cannot support the entire helm feature set."*
Among the features it will not add, the same page lists *"private repository or registry authentication"* and *"OCI registries"*.

No release is created, so there are no revisions and no `helm rollback`, and hooks are rendered as ordinary objects: *"By default the inflation process used by Kustomize will render all the contents of the templates directory, which can result in output different than what you get when using `helm install`."*

With the `helm create` scaffold, the test Pod annotated `helm.sh/hook: test` appears in the output as a plain Pod.
`skipTests: true` leaves out the tests, and `skipHooks: true` leaves out every hook, tests included.

## Choosing between them

- **Helm:** an application that other people or teams install with their own values, an application with chart dependencies, or one that needs release history, rollback, hooks, and tests
- **Kustomize:** manifests we own that differ by a few fields between environments, or third-party manifests that need changes their authors did not parameterize, when the output must stay plain YAML in version control
- **Both:** a third-party chart that needs a field its values do not expose, through a post-renderer, so the release lifecycle stays with Helm
