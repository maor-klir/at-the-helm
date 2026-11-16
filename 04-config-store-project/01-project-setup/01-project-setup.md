# Setting up the config-store project

## Overview

In this exercise, we'll create the repository for config-store, the Express application with a PostgreSQL database that the next sections package and deploy with Helm, and set up its Node.js project.
The application lives in its own repository, `config-store`, not in this one. The course's version is `lm-academy/config-store`, and its commit `fd45b9a`, "chore(config-store): project setup", is the state at the end of this exercise.

Here's a quick summary of the main steps:

1. Create the `config-store` repository on GitHub, and clone it.
2. Initialize the Node.js project.
3. Create the files for the image build and for Compose.
4. Install the dependencies at exact versions.
5. Keep `node_modules` and `.env` files out of the build context.

## Step-by-step guide

The commands assume Node.js 22 and npm 10, the versions on this machine.

1. **Create the repository:**

   Create a public repository named `config-store` with a README file, the Node `.gitignore` template, and the MIT license.
   In the GitHub web interface, all four are options on the new repository page. With the GitHub CLI, one command creates the repository and clones it into the current directory:

   ```bash
   cd ~/repositories/github/maor-klir
   gh repo create config-store --public --description "Repository hosting the config-store application, used for demonstration in multiple courses." --add-readme --gitignore Node --license mit --clone
   cd config-store
   ```

   GitHub's Node template already ignores what the project must not commit: `node_modules/`, and `.env` and `.env.*`, with `!.env.example` keeping the example file.

2. **Clone the repository:**

   If you created the repository in the web interface, clone it next to this repository, instead of in a separate `apps` directory as the course does:

   ```bash
   cd ~/repositories/github/maor-klir
   git clone git@github.com:maor-klir/config-store.git
   cd config-store
   ```

   The SSH URL needs an SSH key added to your GitHub account; the HTTPS URL, `https://github.com/maor-klir/config-store.git`, works with a token instead.

3. **Initialize the Node.js project:**

   ```bash
   npm init -y --init-license=MIT
   ```

   The npm documentation describes the flag: "You can also use `-y`/`--yes` to skip the questionnaire altogether."
   npm fills `description` from the README, and `repository`, `bugs`, and `homepage` from the git remote.

   The license would default to ISC: the `init-license` setting is "The value `npm init` should use by default for the package license.", and its default is `"ISC"`.
   `--init-license=MIT` makes `package.json` match the repository's `LICENSE` file.

4. **Create the project files:**

   ```bash
   touch Dockerfile .dockerignore compose.yaml
   mkdir src
   ```

   The Docker documentation names the Compose file: "The default path for a Compose file is `compose.yaml` (preferred) or `compose.yml` that is placed in the working directory."
   `docker-compose.yaml` still works, "for backwards compatibility of earlier versions."
   Git doesn't track an empty directory, so `src` appears in a commit only once it holds a file.

5. **Install the dependencies:**

   ```bash
   npm install express@4.22.3 sequelize@6.37.8 pg@8.23.1 pg-hstore@2.3.4 body-parser@1.20.9 cors@2.8.6 --save-exact
   ```

   | Package | Purpose, from its npm description |
   |---|---|
   | `express` | "Fast, unopinionated, minimalist web framework" |
   | `sequelize` | "a promise-based Node.js ORM tool for Postgres, MySQL, MariaDB, SQLite, Microsoft SQL Server…" |
   | `pg` | "PostgreSQL client - pure javascript & libpq with the same API" |
   | `pg-hstore` | "A module for serializing and deserializing JSON data into hstore format" |
   | `body-parser` | "Node.js body parsing middleware" |
   | `cors` | "Node.js CORS middleware" |

   `--save-exact` writes the versions without a range: "Dependencies saved to package.json will be configured with an exact version rather than using npm's default semver range operator."
   `package.json` lists `"express": "4.22.3"`, not `"^4.22.3"`, so `npm install` always installs the same versions, which `package-lock.json` also records.

   **The versions differ from the course's:** the course pins `express@4.21.1`, `sequelize@6.37.5`, `pg@8.13.1`, `body-parser@1.20.3`, `cors@2.8.5`, and `nodemon@3.1.7`.
   Installed today, those report `6 vulnerabilities (2 moderate, 4 high)` from `npm audit`, in `body-parser`, Express's `path-to-regexp`, and `qs`.

   The versions above are the latest releases in the same major versions, with the same APIs. They leave `4 moderate severity vulnerabilities`, in `nodemon`'s `minimatch` and `sequelize`'s `uuid`, whose fixes need new major versions.
   Express 5 is the current major version, but the course's code is written for Express 4.

6. **Add `nodemon` as a dev dependency:**

   ```bash
   npm install nodemon@3.1.14 --save-dev --save-exact
   ```

   `nodemon` is a "Simple monitor script for use during development of a Node.js app.": it restarts the application when a file changes.
   `--save-dev` puts it under `devDependencies`; in the npm documentation: "`-D, --save-dev`: Package will appear in your `devDependencies`."

7. **Keep files out of the build context:**

   Add two lines to `.dockerignore`:

   ```text
   node_modules
   .env*
   ```

   The Docker documentation describes the file: "You can use a `.dockerignore` file to exclude files or directories from the build context. This helps avoid sending unwanted files and directories to the builder, improving build speed, especially when using a remote builder."
   `node_modules` is installed inside the image instead, and `.env*` keeps local secrets out of the image.

## Conclusion

In this exercise, we created the `config-store` repository, initialized its Node.js project with exact dependency versions, and prepared the files for the image and for Compose.
`package.json` now matches the course's commit `fd45b9a`, apart from the newer versions, the MIT license, and the repository links npm read from the git remote.
