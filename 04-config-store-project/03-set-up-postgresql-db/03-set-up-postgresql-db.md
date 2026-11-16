# Setting up the PostgreSQL database

## Overview

In this exercise, we'll add a PostgreSQL service to the Compose setup, connect the application to it with Sequelize, and make the application wait until the database accepts connections.
Here's a quick summary of the main steps:

1. Keep the database credentials in a `.env` file that Compose reads.
2. Add a `db` service with a named volume, and pass the application a `DB_URL`.
3. Connect with Sequelize, and start the server only after the connection works.
4. Make the application wait for a healthy database instead of racing it.

## Step-by-step guide

Run the commands from the `config-store` repository, `~/repositories/github/maor-klir/config-store`.

1. **Create the `.env` file:**

   ```text
   DB_USER=config_store_user
   DB_PASSWORD=<a local password>
   DB_NAME=config_store
   ```

   These credentials are for local development only. Once the application runs as an image, it receives a complete `DB_URL` from outside instead.
   The Node `.gitignore` template ignores `.env`, so the file stays out of the repository.

   Compose reads it on its own: "When executed without an explicit `--env-file` flag, Compose searches for an `.env` file in the project directory and loads values both for self-configuration and interpolation."
   Without it, every variable is empty, and Compose warns: `The "DB_USER" variable is not set. Defaulting to a blank string.`

2. **Add the database to `compose.yaml`:**

   ```yaml
   services:
     app:
       build:
         context: .
         target: development
       ports:
         - 3000:80
       environment:
         - PORT=80
         - DB_URL=postgresql://${DB_USER}:${DB_PASSWORD}@db:5432/${DB_NAME}
       develop:
         watch:
           - action: sync
             path: ./src
             target: /app/src
       depends_on:
         db:
           condition: service_healthy
       networks:
         - config-store-net
     db:
       image: postgres:17.12
       environment:
         - POSTGRES_USER=${DB_USER}
         - POSTGRES_PASSWORD=${DB_PASSWORD}
         - POSTGRES_DB=${DB_NAME}
       healthcheck:
         test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
         interval: 5s
         timeout: 5s
         retries: 5
         start_period: 30s
       volumes:
         - type: volume
           source: postgres-data
           target: /var/lib/postgresql/data
       networks:
         - config-store-net

   networks:
     config-store-net:

   volumes:
     postgres-data:
   ```

   `${DB_USER}` and the other references are replaced with the values from `.env`. In `DB_URL`, the host is `db`, the service name, which the shared network resolves.
   The image's documentation describes the variables: `POSTGRES_PASSWORD` "must not be empty or undefined", and `POSTGRES_USER` creates a user "with superuser power and a database with the same name", unless `POSTGRES_DB` names the database.

   **The image tag:** the course uses `postgres:17.1`; `17.12` is the latest release of PostgreSQL 17.
   PostgreSQL 18 is the current major version, but its image moved the data directory: "For 18 it is `/var/lib/postgresql/18/docker`", and the volume has to target `/var/lib/postgresql` instead.

   **The volume keeps the data:** the image's documentation warns, for PostgreSQL 17 and below, to "Mount the data volume at `/var/lib/postgresql/data`", or the data goes to an anonymous volume and "won't persist when the container is deleted and re-created."

   The `healthcheck` and `condition: service_healthy` come in step 5. The course's `depends_on` lists only `- db`.

3. **Connect with Sequelize:**

   Create `src/db.js`:

   ```javascript
   const { Sequelize } = require('sequelize');

   const sequelize = new Sequelize(process.env.DB_URL, {
     dialect: 'postgres',
   });

   module.exports = sequelize;
   ```

   The Sequelize documentation describes the two ways to connect: "This can be done by either passing the connection parameters separately to the Sequelize constructor or by passing a single connection URI".
   The URI already names the dialect, `postgresql://`, so `dialect: 'postgres'` repeats it.

4. **Start the server after the connection:**

   In `src/index.js`, require the module, and replace the `app.listen` call with a chain that connects first:

   ```javascript
   const db = require('./db');
   ```

   ```javascript
   db.authenticate()
     .then(() => {
       console.log('Connected to PostgreSQL.');
       return db.sync();
     })
     .then(() => {
       console.log('Database synchronized, starting server.');
       app.listen(port, () => {
         console.log(`Server running on port ${port}`);
       });
     })
     .catch((err) => {
       console.error('Unable to connect to DB');
       console.error(err);
     });
   ```

   "You can use the `.authenticate()` function to test if the connection is OK".
   `db.sync()` creates the tables for the models the application defines, "This creates the table if it doesn't exist (and does nothing if it already exists)"; exercise 04 adds the first model.
   Each step returns a promise, so returning `db.sync()` makes the next `.then` wait for it, and `.catch` handles a failure in either step.

5. **Wait for a healthy database:**

   With only `depends_on: - db`, the first start fails:

   ```text
   app-1   | Unable to connect to DB
   app-1   | ConnectionRefusedError [SequelizeConnectionRefusedError]: connect ECONNREFUSED 172.20.0.2:5432
   app-1   | [nodemon] clean exit - waiting for changes before restart
   ```

   The Compose documentation explains why: "On startup, Compose does not wait until a container is "ready", only until it's running."
   After the error, the application exits, and `nodemon` waits for a file change, which is why the course's fix is to save `index.js` again.

   The documented fix is a health check: "`service_healthy`. This specifies that a dependency is expected to be “healthy”, which is defined with `healthcheck`, before starting a dependent service."
   `pg_isready` reports whether the server accepts connections, and `$$` passes a literal `$` to the container, so the shell there reads `POSTGRES_USER` and `POSTGRES_DB`.

6. **Run the stack:**

   ```bash
   docker compose up --build --watch
   ```

   Compose starts the database, waits for it, and then starts the application:

   ```text
    Container config-store-db-1 Waiting
    Container config-store-db-1 Healthy
   app-1   | Executing (default): SELECT 1+1 AS result
   app-1   | Connected to PostgreSQL.
   app-1   | Executing (default): SELECT 1+1 AS result
   app-1   | Database synchronized, starting server.
   app-1   | Server running on port 80
   ```

   The `Executing (default):` lines are Sequelize's query log: "By default, Sequelize will log into the console for every SQL query it performs."
   `curl localhost:3000` still returns `Hello world!`.

7. **Stop the stack:**

   ```bash
   docker compose down
   ```

   `down` removes the containers and the network, and keeps the `config-store_postgres-data` volume, so the data survives the next `up`. `docker compose down -v` also removes the volume, and with it the data.

## Conclusion

In this exercise, we added a PostgreSQL service with a named volume, passed the application its connection URL from `.env` values, and started the server only after Sequelize connected.
A health check makes the application wait for the database instead of failing on the first start.
