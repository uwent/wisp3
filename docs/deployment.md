# Deployment

WISP 3 deploys with Capistrano. On each server it runs as two **systemd user services** owned by `deploy`, so deploys restart them without sudo:

- `wisp3-web`: Puma on `127.0.0.1:3100`, behind nginx
- `wisp3-jobs`: the Solid Queue worker (weather refresh, alerts and other background jobs)

| Stage | Host | URL | Rails env |
|---|---|---|---|
| staging | `dev.agweather.cals.wisc.edu` (SSH port 216) | https://dev.wisp.cals.wisc.edu | `staging` |
| production | new server, hostname TBD (`PRODUCTION_HOST`) | https://wisp.cals.wisc.edu | `production` |

The staging host also runs ag-weather and the legacy WISP staging app. WISP 3 takes over the `dev.wisp.cals.wisc.edu` site; legacy files in `~/wisp` are left alone.

## Routine deploys

```bash
cap staging deploy                 # deploys main; BRANCH=some-branch cap staging deploy for others
cap staging systemd:status         # service status
ssh -p 216 deploy@dev.agweather.cals.wisc.edu journalctl --user -u wisp3-web -f    # logs (also wisp3-jobs)
```

Each deploy installs npm packages, builds the Vite assets, runs `db:prepare` (migrations), and restarts both services.

## First-time setup on a server

Run these once per server. Staging shown; for production, use the `production` stage, key and credentials, and set `PRODUCTION_HOST`.

### 1. Check the prerequisites (as `deploy`)

```bash
ssh -p 216 deploy@dev.agweather.cals.wisc.edu
rbenv versions                                   # needs 4.0.5 (rbenv install 4.0.5 if missing)
node -v                                          # needs v24.x on the non-interactive PATH, see below
loginctl show-user deploy --property=Linger      # needs Linger=yes (already confirmed on staging)
```

Capistrano runs commands in a non-interactive shell. If `ssh -p 216 deploy@dev.agweather.cals.wisc.edu 'node -v'` fails but `node -v` works after logging in, Node is only on the interactive PATH. Install it system-wide, or add its `bin` directory to `default_env[:PATH]` in `config/deploy/staging.rb`.

### 2. Create the database role

The role's password is in the stage's Rails credentials. On your machine:

```bash
bin/rails credentials:show --environment staging    # database.password
```

On the server, as a Postgres superuser:

```sql
CREATE ROLE wisp3 LOGIN CREATEDB PASSWORD '<database.password from credentials>';
```

`CREATEDB` lets the first deploy create `wisp3_staging`, `wisp3_staging_cache` and `wisp3_staging_queue`. If that isn't allowed, create those three databases owned by `wisp3` instead.

### 3. Copy the credentials key

The key decrypts `config/credentials/staging.yml.enc`. It is never committed; keep a copy in a password manager.

```bash
ssh -p 216 deploy@dev.agweather.cals.wisc.edu 'mkdir -p ~/wisp3/shared/config/credentials'
scp -P 216 config/credentials/staging.key deploy@dev.agweather.cals.wisc.edu:wisp3/shared/config/credentials/
```

### 4. Install the services and deploy

```bash
cap staging deploy:check
cap staging systemd:install
cap staging deploy
```

### 5. Point nginx at Puma (needs sudo)

Replace the existing `dev.wisp.cals.wisc.edu` site (currently the legacy app) with a reverse proxy to `127.0.0.1:3100`, keeping its TLS certificate lines. See [config/deploy/nginx.conf.example](../config/deploy/nginx.conf.example). Then run `sudo nginx -t && sudo systemctl reload nginx`.

### 6. Verify

- `curl https://dev.wisp.cals.wisc.edu/up` returns 200
- Sign up, receive the confirmation email (sent with the host's `sendmail`), and sign in with both a password and an emailed link
- `cap staging systemd:status` shows both services active
