# Using template functions and pipelines

## Overview

In this session, we'll explore the template functions available in Helm and how to combine them in pipelines to produce valid YAML.

Here’s a brief summary of the steps you’ll want to take:

1. Copy the `intro-go-templating` chart into a new `go-templating-deep-dive` chart.
2. Find the string, dictionary, list, and logic functions in Helm's template function list.
3. See why operators such as `and` come first, like any other function.
4. Create lists and dictionaries with `list` and `dict`, and turn them into valid YAML with `toYaml` and `nindent`.

## Step-by-step guide

Run the commands from this folder. The chart in `go-templating-deep-dive/` is the end state of this exercise.
To follow the steps, copy the chart from section 02's last templating exercise, `../../02-creating-your-own-helm-charts/04-intro-to-go-templating-part-3/intro-go-templating`, into an empty directory as `go-templating-deep-dive`, and edit that copy.

1. **Create the chart:**

   In the copied chart's `Chart.yaml`, rename the chart:

   ```yaml
   apiVersion: v2
   name: go-templating-deep-dive
   version: 0.1.0
   appVersion: 0.1.0
   ```

   `values.yaml` stays as it is. `templates/sandbox.yaml` isn't a Kubernetes object, so this chart is only for `helm template`.

2. **Explore the function list:**

   Helm's documentation lists every template function on one page, the Template Function List: "Helm includes many template functions you can take advantage of in templates. They are listed here and broken down by the following categories".
   The 18 categories range from String, Lists, and Dictionaries to Logic and Flow Control, Type Conversion, Semantic Versions, and Cryptographic and Security.

   - **String:** tests such as `contains`, `hasPrefix`, and `hasSuffix`, trimming with `trim`, and random strings with `randAlphaNum`.
   - **Dictionaries:** `dict` creates one, and `hasKey`, `deepCopy`, and `merge` work on them. `merge` combines default labels with labels from the user, for example: "Merge two or more dictionaries into one, giving precedence to the dest dictionary".
   - **Lists:** `list` creates one, and `append`, `first`, `has`, and others work on them.

   When a template needs an operation, this page is the place to look for a function that already does it.

3. **Understand the function syntax:**

   Comparisons and logical operators are functions too, so they follow the function syntax: the function name first, then its arguments.
   Instead of `value1 && value2`, a template writes `and value1 value2`.

   The function list describes `and` as returning "the boolean AND of two or more arguments (the first empty argument, or the last argument)".
   `{{ and true false }}` renders `false`, `{{ and 1 "" 3 }}` renders an empty string, and `{{ and 1 2 3 }}` renders `3`.

   Some functions take a fixed number of arguments; others, such as `and` and `list`, take any number.

4. **Render a list:**

   Replace the contents of `templates/sandbox.yaml` with a list:

   ```yaml
   list: {{ list 1 2 3 }}
   ```

   ```bash
   helm template go-templating-deep-dive
   ```

   The output is `list: [1 2 3]`, which looks like a list but is a string: the way Go prints the list, the same form the function list uses in its own example, "The above creates a list of `[1 2 3 4 5]`."

5. **Convert the list to YAML:**

   `toYaml` turns the list into YAML. The function list describes it: "The `toYaml` and `toYamlPretty` functions encode an object (list, slice, array, dict, or object) into an indented YAML string."

   ```yaml
   list: {{ list 1 2 3 | toYaml }}
   ```

   The render fails with `yaml: block sequence entries are not allowed in this context`.
   `helm template go-templating-deep-dive --debug` prints the rendered YAML that failed to parse: the first item lands on the key's line, `list: - 1`.

   Moving the action to its own line works:

   ```yaml
   list:
   {{ list 1 2 3 | toYaml }}
   ```

6. **Indent with `nindent`:**

   The function list describes `nindent`: "The `nindent` function is the same as the indent function, but prepends a new line to the beginning of the string."
   That new line lets the action stay on the key's line:

   ```yaml
   list: {{ list 1 2 3 | toYaml | nindent 2 }}
   ```

   ```text
   list:
     - 1
     - 2
     - 3
   ```

   With `indent 2` instead, which adds no new line, the render fails again with `block sequence entries are not allowed in this context`.
   That's why charts use `nindent` far more often than `indent`.

7. **Match the indentation to the nesting:**

   The indent width has to fit where the value sits. Under nested keys, `nindent 2` puts the items at the level of `values`:

   ```yaml
   list:
     values:
       example: {{ list 1 2 3 | toYaml | nindent 2 }}
   ```

   The render fails with `yaml: line 3: did not find expected key`, and `--debug` shows why:

   ```text
   list:
     values:
       example:
     - 1
     - 2
     - 3
   ```

   The items need at least the indentation of `example`, four spaces. Six spaces, two more than the key, is easier to read, and that's what the chart in this folder uses: `{{ list 1 2 3 | toYaml | nindent 6 }}`.

8. **Build a dictionary:**

   `dict` takes its arguments as key-value pairs: "Creating dictionaries is done by calling the `dict` function and passing it a list of pairs."
   A value can be another dictionary, created with `dict` in parentheses:

   ```yaml
   my-dict: {{ dict "primitive" "my string" "complex" (dict "key1" "value1") }}
   ```

   Without `toYaml`, the render succeeds, but the value is Go's string form of the dictionary: `map[complex:map[key1:value1] primitive:my string]`.
   With `toYaml` alone, the render fails with `yaml: mapping values are not allowed in this context`, for the same reason as the list.

   Adding `nindent 2` gives valid YAML. This is the file in `go-templating-deep-dive/templates/sandbox.yaml`:

   ```yaml
   list:
     values:
       example: {{ list 1 2 3 | toYaml | nindent 6 }}

   my-dict: {{ dict "primitive" "my string" "complex" (dict "key1" "value1") | toYaml | nindent 2 }}
   ```

   ```text
   list:
     values:
       example:
         - 1
         - 2
         - 3

   my-dict:
     complex:
       key1: value1
     primitive: my string
   ```

   `toYaml` writes the dictionary's keys in alphabetical order, so `complex` comes before `primitive`.

## Conclusion

In this exercise, we found functions in Helm's Template Function List, saw that operators such as `and` are functions with the same syntax as any other, and turned lists and dictionaries into valid YAML with `toYaml` and `nindent`, matching the indentation to where the value sits.
