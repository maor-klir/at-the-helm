#helm #kubernetes #templating

# Values and release information in a chart

A chart becomes reusable when two kinds of settings come from outside its templates.
Settings that differ between installations come from values, and names and labels that must differ between releases come from `.Release`.

The rules for both come from three places: Kubernetes, for object names and selectors; YAML, for value types; and Helm, for release names and the metadata it adds to objects.

## Values as the chart's interface

A chart's `values.yaml` defines what its users can change: a template can be changed only through the values it reads (see **03 - Helm vs. Kustomize**), and users override them with `--values` and `--set` (see **13 - Overriding chart values**).
Each value is documented in `values.yaml` itself (see **02 - Benefits and limitations of Helm**).

**`## @param` comments document values in a machine-readable form:** they follow the format of Bitnami's readme-generator-for-helm, a tool to *"Autogenerate Helm Charts READMEs' tables based on values YAML file metadata."*
Its format is *"For a parameter: `## @param fullKeyPath [modifier?] Description`."*

```yaml
## @param service.enabled Whether to deploy the service altogether or not
## @param service.type The type of service in front of the Nginx pods
## @param service.port The port where the service is receiving requests
service:
  enabled: true
  type: ClusterIP
  port: 80
```

**One value can set several fields that must agree:** our chart's `containerPorts.http` sets both the container's `containerPort` and the Service's `targetPort`.
`kubectl explain` defines the Service fields: `port` is *"The port that will be exposed by this service."*, and `targetPort` is the *"Number or name of the port to access on the pods targeted by the service."*

With one value behind both, `--set containerPorts.http=8080` renders `containerPort: 8080` and `targetPort: 8080`, while `port` stays 80.

### Types and quoting

YAML reads an unquoted scalar by its form.
`tag: 1.27.0` stays a string, but `tag: 1.10` is the number 1.1, and an image built from it renders as `nginx:1.1`.

Helm's best practices make the rule explicit: *"`foo: false` is not the same as `foo: "false"`."*
Their advice is to quote all strings in `values.yaml`.

**`quote` adds quotes in the template:** the function list describes it as wrapping *"a string in double quotes"*, so `{{ .Values.image.tag | quote }}` renders `"1.27.0"`.
It can't repair a value YAML has already converted: with an unquoted `tag: 1.10`, it renders `"1.1"`.

Without `quote`, a string value can also change type in the rendered manifest: a value of `"true"` renders as a bare `true`, which YAML reads as a boolean.

Helm's chart tips draw the line between the two cases: *"When you are working with string data, you are always safer quoting the strings than leaving them as bare words"*, *"But when working with integers do not quote the values."*
So `replicas` and the ports stay unquoted in the templates; `{{ .Values.containerPorts.http | quote }}` would render the string `"80"`.

## Names that differ per release

Kubernetes allows one object of each kind per name in a namespace: *"Each object in your cluster has a Name that is unique for that type of resource."*
A chart with fixed names can therefore be installed only once per namespace.

Helm's chart template guide calls fixed names out: *"Hard-coding the `name:` into a resource is usually considered to be bad practice. Names should be unique to a release."*
With fixed names, a second release fails on the first object the other release already owns:

```text
Error: INSTALLATION FAILED: unable to continue with install: Service "nginx-svc" in namespace "nginx" exists and cannot be imported into the current release: invalid ownership metadata; annotation validation error: key "meta.helm.sh/release-name" must equal "local-nginx-2": current value is "local-nginx"
```

**Release names are unique within a namespace:** a second install under a name that's still in use fails with `release name check failed: cannot reuse a name that is still in use`.
A name built as `{{ .Release.Name }}-{{ .Chart.Name }}`, such as `local-nginx-nginx`, is unique for the same reason.

The guide also gives the length limits: *"The `name:` field is limited to 63 characters because of limitations to the DNS system. For that reason, release names are limited to 53 characters."*

**`helm create` builds names with a helper:** its `fullname` named template truncates the name to 63 characters and drops the chart name when the release name already contains it.
A release `local-demo` of a chart `demo` gets objects named `local-demo`, while a release `web` gets `web-demo`.

## Labels and selectors per release

A Deployment's selector and a Service's selector have to match only the release's own Pods.
With a label such as `app: nginx` alone, two releases of the same chart select each other's Pods.

The Kubernetes Deployment documentation warns against that overlap:

> *"Do not overlap labels or selectors with other controllers (including other Deployments and StatefulSets). Kubernetes doesn't stop you from overlapping, and if multiple controllers have overlapping selectors those controllers might conflict and behave unexpectedly."*

Adding a label from `.Release.Name` to every selector keeps the releases apart.
With two releases installed, the EndpointSlice of `local-nginx-nginx-svc` lists only the three `local-nginx-nginx-…` Pods.

Helm's best practices name the two labels: `app.kubernetes.io/name` for the application, and `app.kubernetes.io/instance` for the release, *"This should be the `{{ .Release.Name }}`. It aids in differentiating between different instances of the same application."*
The `helm create` scaffold uses both as its selector labels (see **01 - The role of Helm in Kubernetes**).

A Deployment's selector is immutable, so selector labels are chosen before the first install; changing them later makes `helm upgrade` fail for existing releases.

## What Helm adds to the objects it creates

Helm adds a label and two annotations to every object it creates, whether the chart sets them or not:

```text
Labels:                 app=nginx
                        app.kubernetes.io/managed-by=Helm
                        release=local-nginx
Annotations:            deployment.kubernetes.io/revision: 1
                        meta.helm.sh/release-name: local-nginx
                        meta.helm.sh/release-namespace: nginx
```

The annotations record which release owns the object, and they're what the ownership check in the error above compares (see **02 - Benefits and limitations of Helm**).

**Objects that Kubernetes creates get less:** the Deployment controller copies the Deployment's annotations, including the two `meta.helm.sh/` ones, to its ReplicaSet, but the ReplicaSet's labels come from the Pod template, so it has no `managed-by` label.
The Pods get neither: their labels come only from the Pod template, and they have no annotations.

## Optional objects

Wrapping a whole template in an `if` makes the object optional:

```yaml
{{- if .Values.service.enabled }}
apiVersion: v1
kind: Service
# …
{{ end }}
```

With `service.enabled` false, the Service document disappears from the rendered manifests; `helm template … -s templates/service.yaml` then reports `could not find template templates/service.yaml in chart`.

Helm's control structures guide lists what counts as false: *"a boolean false"*, *"a numeric zero"*, *"an empty string"*, *"a `nil` (empty or null)"*, and *"an empty collection"*; *"Under all other conditions, the condition is true."*

**The string `"false"` counts as true:** `--set-string service.enabled=false`, or `enabled: "false"` in a values file, is a non-empty string, and the Service is still rendered.
A missing value counts as false: with `--set service.enabled=null`, which removes the key, no Service is rendered, so the default belongs in `values.yaml`.

**Turning an object on or off is an upgrade:** `helm upgrade --set service.enabled=true` creates the Service in a new revision, and setting it back to false deletes it, because Helm removes the objects a revision no longer renders (see **14 - Upgrading releases**).

## Verify

From the folder that holds our final `creating-charts/nginx` chart, the names, labels, and the shared port render as described:

```bash
helm template local-nginx creating-charts/nginx | grep -E '^kind|  name:|release:'
helm template creating-charts/nginx --set containerPorts.http=8080 | grep -E 'containerPort|targetPort|port:'
```

The Service follows `service.enabled`, but not a string `"false"`:

```bash
helm template creating-charts/nginx --set service.enabled=false | grep '^kind'
helm template creating-charts/nginx --set-string service.enabled=false | grep '^kind'
```

The first command renders only `kind: Deployment`; the second renders the Service as well.
