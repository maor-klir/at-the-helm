# Implementing the key-value API

## Overview

In this exercise, we'll add a Sequelize model for key-value pairs and an Express router with the five routes that read, create, update, and delete them under `/api/kv`.
Here's a quick summary of the main steps:

1. Stop the Compose stack while the model is written.
2. Define the `KV` model.
3. Write the routes, and mount them under `/api`.
4. Start the stack, and test every route with `curl`.

## Step-by-step guide

Run the commands from your clone of the `config-store` repository, created in exercise 01.

1. **Stop the stack:**

   Stop `docker compose up --watch` with Ctrl+C before writing the model.
   With the watch running, every save restarts the application, and `db.sync()` runs against whatever the model file holds at that moment.

   `sync()` only creates missing tables: in the Sequelize documentation, it "creates the table if it doesn't exist (and does nothing if it already exists)".
   A table created from a half-written model keeps its wrong columns until it's dropped.

2. **Define the model:**

   Create `src/models.js`:

   ```javascript
   const { DataTypes } = require('sequelize');
   const db = require('./db');

   const KV = db.define('KV', {
     key: {
       type: DataTypes.STRING,
       allowNull: false,
       unique: true,
     },
     value: {
       type: DataTypes.STRING,
       allowNull: false,
     },
   });

   module.exports = { KV };
   ```

   Keys are required and unique; values are required and may repeat. The course's file requires `./db` twice, as `db` and as `sequelize`; one is enough.

3. **Write the routes:**

   Create `src/routes.js`:

   ```javascript
   const express = require('express');
   const { KV } = require('./models');

   const apiRouter = express.Router();

   apiRouter.get('/kv', async (req, res) => {
     try {
       const kvs = await KV.findAll();
       return res.json({ data: kvs });
     } catch (err) {
       return res.status(500).json({ error: err.message });
     }
   });

   apiRouter.get('/kv/:key', async (req, res) => {
     const { key } = req.params;

     try {
       const kv = await KV.findOne({ where: { key } });

       if (kv) {
         return res.json({ data: kv });
       } else {
         return res.status(404).json({ error: 'key not found' });
       }
     } catch (err) {
       return res.status(500).json({ error: err.message });
     }
   });

   apiRouter.post('/kv', async (req, res) => {
     const { key, value } = req.body;

     if (!key || !value) {
       return res
         .status(400)
         .json({ error: 'both key and value fields are required.' });
     }

     try {
       const existingKv = await KV.findOne({ where: { key } });

       if (existingKv) {
         return res.status(400).json({ error: 'key already present in DB.' });
       } else {
         const newKv = await KV.create({ key, value });
         return res.status(201).json({ data: newKv });
       }
     } catch (err) {
       return res.status(500).json({ error: err.message });
     }
   });

   apiRouter.put('/kv/:key', async (req, res) => {
     const { key } = req.params;
     const { value } = req.body;

     if (!value) {
       return res.status(400).json({ error: 'value field is required.' });
     }

     try {
       const [updatedCount] = await KV.update({ value }, { where: { key } });

       if (updatedCount > 0) {
         const updatedKv = await KV.findOne({ where: { key } });

         if (updatedKv) {
           return res.json({ data: updatedKv });
         } else {
           return res.status(404).json({ error: 'key not found' });
         }
       } else {
         return res.status(404).json({ error: 'key not found' });
       }
     } catch (err) {
       return res.status(500).json({ error: err.message });
     }
   });

   apiRouter.delete('/kv/:key', async (req, res) => {
     const { key } = req.params;

     try {
       const deleted = await KV.destroy({ where: { key } });

       if (deleted > 0) {
         return res.sendStatus(204);
       } else {
         return res.status(404).json({ error: 'key not found' });
       }
     } catch (err) {
       return res.status(500).json({ error: err.message });
     }
   });

   module.exports = apiRouter;
   ```

   Successful responses wrap the result in `data`, and errors in `error`.
   `KV.update` returns an array whose first element is the number of updated rows, so a `0` means the key doesn't exist.

   The delete route needs `res.sendStatus(204)`. With `res.status(204)` alone, the status is set but the response is never sent: the request hangs, and `curl -m 5` gives up with exit code 28.

4. **Mount the router:**

   In `src/index.js`, require the router, and mount it after the JSON parser:

   ```javascript
   const apiRouter = require('./routes');
   ```

   ```javascript
   app.use(bodyParser.json());
   app.use('/api', apiRouter);
   ```

   The router's `/kv` routes now answer under `/api/kv`. `GET /` still returns `Hello world!`.

5. **Start the stack:**

   ```bash
   docker compose up --build --watch
   ```

   On startup, `sync()` creates the table. Sequelize names it after the model in the plural, `"KVs"`:

   ```text
   app-1   | Executing (default): CREATE TABLE IF NOT EXISTS "KVs" ("id"   SERIAL , "key" VARCHAR(255) NOT NULL UNIQUE, "value" VARCHAR(255) NOT NULL, "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL, "updatedAt" TIMESTAMP WITH TIME ZONE NOT NULL, PRIMARY KEY ("id"));
   ```

   Sequelize adds the `id` key and the two timestamps on its own.

6. **Test every route:**

   In a second terminal:

   ```bash
   curl localhost:3000/api/kv
   curl -X POST -H 'Content-Type: application/json' -d '{"key":"color","value":"blue"}' localhost:3000/api/kv
   curl -X PUT -H 'Content-Type: application/json' -d '{"value":"green"}' localhost:3000/api/kv/color
   curl -X DELETE -i localhost:3000/api/kv/color
   ```

   | Request | Status | Body |
   |---|---|---|
   | `GET /api/kv` on an empty table | 200 | `{"data":[]}` |
   | `POST /api/kv` with `color` and `blue` | 201 | `{"data":{"id":1,"key":"color","value":"blue",…}}` |
   | the same `POST` again | 400 | `{"error":"key already present in DB."}` |
   | `POST /api/kv` without `value` | 400 | `{"error":"both key and value fields are required."}` |
   | `GET /api/kv/color` | 200 | `{"data":{"id":1,"key":"color","value":"blue",…}}` |
   | `GET /api/kv/missing` | 404 | `{"error":"key not found"}` |
   | `PUT /api/kv/color` with `green` | 200 | `{"data":{…,"value":"green",…}}` |
   | `PUT /api/kv/color` without `value` | 400 | `{"error":"value field is required."}` |
   | `DELETE /api/kv/color` | 204 | none |
   | the same `DELETE` again | 404 | `{"error":"key not found"}` |

   A form-encoded body, `-d 'key=a&value=b'`, also gets a 400: only JSON is parsed.

7. **Stop the stack:**

   ```bash
   docker compose down
   ```

   The pairs stay in the `config-store_postgres-data` volume for the next `up`.

## Conclusion

In this exercise, we added the `KV` model and the five `/api/kv` routes, and tested each status code with `curl`.
The application is complete: exercise 05 builds its production image and pushes it to a registry.
