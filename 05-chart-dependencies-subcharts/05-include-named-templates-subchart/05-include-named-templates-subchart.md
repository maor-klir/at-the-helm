# Including a subchart's named template in the parent chart

## Overview

In this exercise, we'll include a named template from `demo-subchart` in a template of config-store, and see that the result depends on the context each include passes.
Here's a quick summary of the main steps:

1. Include `demo-subchart.fullname` in a new template of the parent chart.
2. Set `nameOverride` in both charts, and compare the two results.
3. See what the include depends on: the subchart, the template's name, and the caller's values.
4. Undo the changes.

## Step-by-step guide

The chart doesn't change in this exercise: the course undoes its changes at the end, so exercise 04's chart is both the start and the end state.
Copy exercise 04's `subcharts` directory into an empty directory, and run the commands from `config-store/`.

The behaviour here is that of application subcharts; library charts, in the advanced topics section, are made for sharing templates.

1. **Include the subchart's template:**

   Create `templates/from-subchart.yaml` in config-store, with a single YAML comment:

   ```yaml
   # test value from subchart: {{ include "demo-subchart.fullname" . }}
   ```

   ```bash
   helm template . | grep -A1 'templates/from-subchart'
   ```

   ```text
   # Source: config-store/templates/from-subchart.yaml
   # test value from subchart: release-name-config-store
   ```

   `demo-subchart.fullname` is defined in `charts/demo-subchart/templates/_helpers.tpl`, and the parent can include it. The Subcharts and Global Values guide: *"Parent charts and subcharts can share templates. Any defined block in any chart is available to other charts."*
   The helper builds the name from `.Release.Name`, `.Chart.Name`, and `.Values.nameOverride` of the dot it receives, and here the dot is config-store's.

2. **Set `nameOverride` in both charts:**

   In config-store's `values.yaml`, set `nameOverride: 'override-from-parent'`. At the end of `charts/demo-subchart/values.yaml`, add:

   ```yaml
   nameOverride: 'override-from-subchart'
   ```

   ```bash
   helm template . | grep -A1 'templates/from-subchart'
   helm template . --show-only charts/demo-subchart/templates/configmap.yaml | grep '^  name:'
   ```

   ```text
   # Source: config-store/templates/from-subchart.yaml
   # test value from subchart: release-name-override-from-parent
     name: release-name-override-from-subchart
   ```

   Both lines come from the same `include "demo-subchart.fullname" .`. In the parent's template, the dot holds config-store's values; in the subchart's ConfigMap, it holds `demo-subchart`'s.
   The parent's `nameOverride` also renames config-store's own Service, Deployment, and ServiceAccount to `release-name-override-from-parent`.

3. **See what the include depends on:**

   | Change | Result |
   |---|---|
   | remove `charts/demo-subchart` and its `dependencies` entry | the render fails with `template: no template "demo-subchart.fullname" associated with template "gotpl"` |
   | define another `demo-subchart.fullname` in config-store's `_helpers.tpl` | the parent's definition wins, and renames the subchart's own ConfigMap too |
   | read `.Values.global.…` in the helper instead | both includes get the value the parent sets under `global` (see exercise 04) |

   Helm parses the templates of the deepest paths first and the parent's last, so for two templates with the same name, the parent's is the one used (from Helm's source, `pkg/engine`). That's why named templates start with the chart's name.

   The course suggests using this pattern sparingly: every template the parent includes from a subchart makes the parent fail without that subchart, and ties it to the subchart's template names.

4. **Undo the changes:**

   Delete `templates/from-subchart.yaml`, set config-store's `nameOverride` back to `''`, and remove `nameOverride` from `demo-subchart`'s `values.yaml`.

## Conclusion

In this exercise, we included `demo-subchart.fullname` from config-store, and saw that the same named template gives different results with the parent's and the subchart's context.
Exercise 06 turns subcharts on and off with conditions and tags.
