# Hosting Jozu on Render Free

The repository contains a `render.yaml` Blueprint for one free Ruby web service
and one free managed PostgreSQL database in Frankfurt. No Redis, background
worker, email provider, or runtime LLM key is required. Solid Cache shares the
application database and stores issued questions and diagnostic state across
restarts. Its approximate 32 MB budget limits cache growth within the free
Postgres database; it is not a hard quota on total database size.

## Free-tier limitations

[Render's free services documentation](https://render.com/docs/free) says the web
service sleeps after 15 minutes without traffic, so opening the app can involve a
cold start. Free PostgreSQL expires after **30 days**, has a **1 GB** storage limit,
and has no managed backups. After expiry, you have 14 days to upgrade before
Render deletes the database. This setup is suitable for trying hosted Jozu;
upgrade the database before expiry if you want uninterrupted ongoing use. Keep
manual backups even during the trial. No paid plan is configured by this Blueprint.

## Local review and your existing profile

```sh
bin/rails db:migrate
USER_ID=1 bin/rails jozu:access_link
```

The migration gives every existing user a private UUIDv4 link without replacing
users, settings, study items, or review history. The command prints a credential:
keep its output private. For your existing Tailscale access, set `APP_URL` to your
current origin (including port), for example:

```sh
USER_ID=1 APP_URL=http://your-tailscale-host:3000 bin/rails jozu:access_link
```

Open the link, bookmark the page, then select **Continue to my profile**. New users
create profiles from `/welcome`. Access links are reusable and do not expire.
Signed-in browsers use an encrypted HttpOnly cookie lasting up to one year;
clearing cookies or signing out does not invalidate the bookmark. The private link
is available again in Settings. Losing the link and all signed-in sessions means
there is no automatic recovery. A home-screen install starts at `/`; if its browser
storage is separate, open your saved link in that browser to restore the profile.

## Deploy after reviewing, committing, and pushing

1. Commit and push the reviewed changes to your Git provider.
2. In Render, create a **Blueprint** from the repository and use `render.yaml`.
3. Supply `RAILS_MASTER_KEY` from your local `config/master.key` in Render's secret
   environment setting. Do not commit it. `DATABASE_URL` is supplied automatically
   from the Blueprint database; Render supplies `PORT` and
   `RENDER_EXTERNAL_HOSTNAME`. The app allows the Render hostname; if adding a
   custom domain, also set `APP_HOST` to that hostname (no scheme or port).
4. The free service runs `bin/render-build.sh`: install gems, compile assets,
   migrate the database, and import the vendored corpus. It does not seed a demo
   account or call an LLM. With no paid pre-deploy hook, migrations happen during
   the build, so future migrations must remain compatible with the running app.
5. Open the Render URL. `/up` is a public boot health check; verify account creation,
   saving a link, diagnostic answers, and quiz answers as a separate smoke check.

Puma runs in single-process mode (`WEB_CONCURRENCY=0`) with three threads to fit
free web-service memory. The database connection pool is shared with Solid Cache.
The included production Dockerfile is not used by this native Ruby Blueprint.

## Transfer your current progress

The corpus import does **not** transfer your personal history. Back up and restore
the whole local database to preserve corpus IDs and their related study records.
Do this before using the hosted app or creating profiles there. Restoring replaces
the destination tables: only use these instructions for your new Jozu database.

After applying the local migrations, create a private backup outside the repository:

```sh
pg_dump --format=custom --no-owner --no-acl \
  --exclude-table-data=solid_cache_entries \
  --file=/private/tmp/jozu-backup.dump jozu_development
```

Copy Render's **external** database URL into a private shell variable
`JOZU_RENDER_DATABASE_URL`. Avoid putting the URL in shell history or sharing it.
Stop/suspend the new web service during the restore so no requests write to it.
Restore only to that new, disposable hosted database:

```sh
pg_restore --clean --if-exists --no-owner --no-acl \
  --dbname="$JOZU_RENDER_DATABASE_URL" /private/tmp/jozu-backup.dump
```

The dump includes the cache table schema but omits transient quiz cache data.
Resume/redeploy the web service afterwards; migrations and corpus import are
idempotent. To obtain the hosted link for the same local user:

```sh
USER_ID=1 APP_URL=https://your-service.onrender.com bin/rails jozu:access_link
```

Use a PostgreSQL client compatible with both the local and hosted database
versions. Verify that Settings and Progress show your existing state. The same
backup/restore approach works for later manual backups: use the hosted database
as the `pg_dump` source instead. Dumps contain access credentials and learning
history, so store them privately and keep them out of Git.

## Access-link privacy

Rails filters the UUID in request paths and parameters. Account pages use
`Cache-Control: private, no-store`, Turbo snapshot caching is disabled, and
`Referrer-Policy: no-referrer` prevents links leaking via referrers. Mutations use
Rails CSRF protection, including the POST that enters a profile. Account creation
is limited to five profiles per IP per hour using the shared production cache.

The URL necessarily remains in bookmarks and browser history. Render or any
upstream proxy may log incoming URLs independently of Rails: check those logging
settings before sharing access widely. Do not add third-party analytics to access
pages. Anyone who obtains a link has the same account access as its owner; there
is no email recovery, account verification, or separate read-only sharing mode.
