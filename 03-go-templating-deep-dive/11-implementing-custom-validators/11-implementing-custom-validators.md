# Implementing custom validators with named templates

## Overview

In this exercise, we'll combine named templates with `fail` into validators: named templates that check a value and stop the render when it's invalid.
Here's what we'll aim to implement:

1. Write a validator for the port range, and call it where the port is used.
2. Return the value from the validator, so the port still renders.
3. Validate each Service's port and type in one validator at the top of the loop.
4. Reuse the port validator inside the Service validator.

## Step-by-step guide

Run the commands from this folder. The chart in `go-templating-deep-dive/` is the end state of this exercise.
It continues from exercise 10's chart, so to follow the steps, copy `../10-validation-functions/go-templating-deep-dive` into an empty directory and edit that copy.

1. **Define a port range validator:**

   In `templates/_helpers.tpl`, add a named template that receives a port as its context:

   ```yaml
   {{/*Expects a port to be passed as the context*/}}
   {{- define "go-templating-deep-dive.validators.portRange" -}}
   {{- $sanitizedPort := int . -}}
   {{- if or (lt $sanitizedPort 1) (gt $sanitizedPort 65535) -}}
   {{- fail "Error: Ports must always be between 1 and 65535." -}}
   {{- end -}}
   {{- end -}}
   ```

   `int` converts a port passed as a string, and leaves an integer as it is.
   `or`, `lt`, and `gt` are functions like any other, so each comparison goes in parentheses (see **31 - Functions and pipelines**).
   The comment above the `define` documents what the context has to be, since nothing else in the template says so.

2. **Call the validator on the port line:**

   In `templates/service.yaml`, pass the port through the validator:

   ```yaml
   port: {{ include "go-templating-deep-dive.validators.portRange" .port }}
   ```

   The space between the template's name and `.port` is required. Written as `"go-templating-deep-dive.validators.portRange".port`, the template fails to parse with `unexpected . after term`.

   ```bash
   helm template go-templating-deep-dive -s templates/service.yaml
   ```

   The render succeeds, but both Services render `port:` with no value: the `include` is replaced by the named template's output, and the validator outputs nothing.
   With `--set services.svc1.port=99999`, the validator stops the render: `Error: execution error at (go-templating-deep-dive/templates/service.yaml:16:15): Error: Ports must always be between 1 and 65535.`

3. **Return the value:**

   A named template returns the text it renders. Output the port after the check, as the last line before the `define`'s `end`:

   ```yaml
   {{- . }}
   ```

   The dash trims the newline before it, so the output is the port alone, and both Services render their ports again, `80` and `30007`.

4. **Validate the whole Service:**

   For more than one check, validate the Service's settings once at the top of the loop instead of on each line.
   Revert the port line to `port: {{ .port }}`, and turn the validator into one that receives the whole Service:

   ```yaml
   {{/*Expects an object with port and type to be passed as the context*/}}
   {{- define "go-templating-deep-dive.validators.service" -}}
   {{- $sanitizedPort := int .port -}}
   {{/*Port validation*/}}
   {{- if or (lt $sanitizedPort 1) (gt $sanitizedPort 65535) -}}
   {{- fail "Error: Ports must always be between 1 and 65535." -}}
   {{- end -}}

   {{/*Service type validation*/}}
   {{- $allowedSvcTypes := list "ClusterIP" "NodePort" -}}
   {{- if not (has .type $allowedSvcTypes) -}}
   {{- fail (printf "Invalid service type %s. Supported values are %s" .type $allowedSvcTypes) -}}
   {{- end -}}
   {{- end -}}
   ```

   It returns nothing, because it only checks. `has` takes the item first and the list second (see **31 - Functions and pipelines**).
   Include it as the first line inside the loop, passing the dot, which holds the current Service's settings; `$svc` works as well (see exercise 08).

   ```bash
   helm template go-templating-deep-dive --set services.svc1.type=ExternalName
   ```

   ```text
   Error: execution error at (go-templating-deep-dive/templates/service.yaml:2:3): Invalid service type ExternalName. Supported values are [ClusterIP NodePort]
   ```

   `%s` prints the list as Go prints it. `join ", " $allowedSvcTypes` turns it into `ClusterIP, NodePort`, which reads better in the message.

5. **Reuse the port validator:**

   A port range check applies to any port, such as `containerPorts.http`, not only to Services.
   Keep `validators.portRange` as its own named template, and include it from the Service validator. This is the end of `go-templating-deep-dive/templates/_helpers.tpl`:

   ```yaml
   {{/*Expects an integer or string to be passed as the context*/}}
   {{- define "go-templating-deep-dive.validators.portRange" -}}
   {{- $sanitizedPort := int . -}}
   {{/*Port validation*/}}
   {{- if or (lt $sanitizedPort 1) (gt $sanitizedPort 65535) -}}
   {{- fail "Error: Ports must always be between 1 and 65535." -}}
   {{- end -}}
   {{- end -}}

   {{/*Expects an object with port and type to be passed as the context*/}}
   {{- define "go-templating-deep-dive.validators.service" -}}
   {{- include "go-templating-deep-dive.validators.portRange" .port -}}

   {{/*Service type validation*/}}
   {{- $allowedSvcTypes := list "ClusterIP" "NodePort" -}}
   {{- if not (has .type $allowedSvcTypes) -}}
   {{- fail (printf "Invalid service type %s. Supported values are: %s" .type (join ", " $allowedSvcTypes)) -}}
   {{- end -}}
   {{- end -}}
   ```

   A named template can include another one. Here, the port validator receives `.port`, and returns nothing, since this version has no `{{- . }}`.
   This is the start of `go-templating-deep-dive/templates/service.yaml`:

   ```yaml
   {{- range $key, $svc := (.Values.services | default dict) }}
   {{ include "go-templating-deep-dive.validators.service" . }}
   ---
   ```

   The two Services render as in exercise 10. Each invalid value stops the render:

   | Value | Error message |
   |---|---|
   | `--set services.svc1.type=ExternalName` | `Invalid service type ExternalName. Supported values are: ClusterIP, NodePort` |
   | `--set services.svc1.port=99999` | `Error: Ports must always be between 1 and 65535.` |
   | `--set services.svc1.port=0` | the same port error |
   | `--set-string services.svc1.port=abc` | the same port error: `int` turns `abc` into `0` |

   Helm already starts every error with `Error:`, so the port message's own prefix repeats: `Error: execution error at (…): Error: Ports must…`.

## Conclusion

In this exercise, we wrote validators as named templates that stop the render with `fail`, either returning the value they check or only checking, and reused one validator inside another.
For rules about the shape of the values, such as allowed types and number ranges, Helm also validates `values.schema.json`, which **36 - Validating values** compares with template validators.
