# Deployment

| Stage | Where | How | URL | Rails env |
|---|---|---|---|---|
| staging | `dev.agweather.cals.wisc.edu` (SSH port 216), local Postgres | Capistrano, systemd user services | https://dev.wisp.cals.wisc.edu | `staging` |
| production | AWS us-east-1: EC2 `wisp-prod` (54.159.70.187), RDS `wisp-prod` (PostgreSQL 18) | Docker Compose, images built on the server | https://wisp.cals.wisc.edu (at launch) | `production` |

Both run the same two processes: the web server (Puma) and the Solid Queue worker (weather refresh, the daily digest, the health check and other background jobs).

- [Staging](#staging-capistrano)
- [Production](#production-docker-on-ec2)

---

## Staging (Capistrano)

On the staging host WISP 3 runs as two **systemd user services** owned by `deploy`, so deploys restart them without sudo:

- `wisp3-web`: Puma on `127.0.0.1:3100`, behind nginx
- `wisp3-jobs`: the Solid Queue worker

The staging host also runs ag-weather and the legacy WISP staging app. WISP 3 takes over the `dev.wisp.cals.wisc.edu` site; legacy files in `~/wisp` are left alone.

### Routine deploys

```bash
cap staging deploy                 # deploys main; BRANCH=some-branch cap staging deploy for others
cap staging systemd:status         # service status
ssh -p 216 deploy@dev.agweather.cals.wisc.edu journalctl --user -u wisp3-web -f    # logs (also wisp3-jobs)
```

Each deploy installs pnpm packages, builds the Vite assets, runs `db:prepare` (migrations), loads the reference data and restarts both services.

### First-time setup

Done once, in October 2026; kept for rebuilding the server.

#### 1. Check the prerequisites (as `deploy`)

```bash
ssh -p 216 deploy@dev.agweather.cals.wisc.edu
rbenv versions                                   # needs 4.0.5 (rbenv install 4.0.5 if missing)
node -v                                          # needs v24.x on the non-interactive PATH, see below
loginctl show-user deploy --property=Linger      # needs Linger=yes (already confirmed on staging)
```

Capistrano runs commands in a non-interactive shell. If `ssh -p 216 deploy@dev.agweather.cals.wisc.edu 'node -v'` fails but `node -v` works after logging in, Node is only on the interactive PATH. Install it system-wide, or add its `bin` directory to `default_env[:PATH]` in `config/deploy/staging.rb`.

#### 2. Create the database role

The role's password is in the staging credentials. On your machine:

```bash
bin/rails credentials:show --environment staging    # database.password
```

On the server, as a Postgres superuser:

```sql
CREATE ROLE wisp3 LOGIN CREATEDB PASSWORD '<database.password from credentials>';
```

`CREATEDB` lets the first deploy create `wisp3_staging`, `wisp3_staging_cache` and `wisp3_staging_queue`. If that isn't allowed, create those three databases owned by `wisp3` instead.

#### 3. Copy the credentials key

The key decrypts `config/credentials/staging.yml.enc`. It is never committed; keep a copy in a password manager.

```bash
ssh -p 216 deploy@dev.agweather.cals.wisc.edu 'mkdir -p ~/wisp3/shared/config/credentials'
scp -P 216 config/credentials/staging.key deploy@dev.agweather.cals.wisc.edu:wisp3/shared/config/credentials/
```

#### 4. Install the services and deploy

```bash
cap staging deploy:check
cap staging systemd:install
cap staging deploy
```

#### 5. Point nginx at Puma (needs sudo)

Add a `wisp3` site in `/etc/nginx/sites-available` (enabled in `sites-enabled`) that reverse-proxies `dev.wisp.cals.wisc.edu` to `127.0.0.1:3100`, reusing the legacy site's TLS certificate lines. Staging keeps the legacy site's config file but no longer enables it for that hostname. See [config/deploy/nginx.conf.example](../config/deploy/nginx.conf.example). Then run `sudo nginx -t && sudo systemctl reload nginx`.

#### 6. Verify

- `curl https://dev.wisp.cals.wisc.edu/up` returns 200 with JSON: `status` is `ok`, or `degraded` once the morning health check (7 am) finds problems or is overdue; `database` is `ok`; `version` is the deployed commit. An uptime monitor can alert on a non-200 response or on `"status":"degraded"`
- Sign up, receive the confirmation email (sent with the host's `sendmail`), and sign in with both a password and an emailed link
- `cap staging systemd:status` shows both services active

---

## Production (Docker on EC2)

The server and database were set up by CALS IT. Each deploy builds the commit's image on the server itself, from a git checkout of the public repo and the [Dockerfile](../Dockerfile), and [config/deploy/compose.production.yaml](../config/deploy/compose.production.yaml) (copied to `/opt/wisp/compose.yaml`) runs it as two containers:

- `web`: Thruster on ports 80 and 443 in front of Puma. Thruster gets and renews the Let's Encrypt certificate for `APP_HOST` by itself, so there's no nginx or certbot.
- `jobs`: the Solid Queue worker (`bin/jobs`).

| Resource | Name | Address |
|---|---|---|
| App server (EC2, Ubuntu 26.04, t3.medium) | `wisp-prod` | 54.159.70.187 (Elastic IP); you log in as yourself with an SSH key |
| Database (RDS PostgreSQL 18) | `wisp-prod` | `wisp-prod.chjgrhbg1z6x.us-east-1.rds.amazonaws.com:5432` |

On the server, everything is in `/opt/wisp`:

| Path | What |
|---|---|
| `.env` | Settings and secrets, edited by hand (step 3), readable only by you |
| `src/` | A clone of `github.com/uwent/wisp3`, checked out at the commit being built |
| `compose.yaml` | The deployed commit's compose file |

- **Nothing here needs AWS permissions.** Deploys use SSH, git and Docker; ECR, SSM and SES aren't used.
- **The database is only reachable from the server** (private subnets; its security group admits the server's). It requires TLS, and the app checks RDS's certificate against [config/rds-global-bundle.pem](../config/rds-global-bundle.pem), which is in the image.
- **SSH (port 22) is open only to the IP addresses IT has on file.** If a connection times out from a new place (home, campus, VPN), send IT your public IP.
- **Secrets never go in the image or the repo.** They're only in `/opt/wisp/.env` and the password manager, so keep the password manager's copy current.
- **Backups are RDS's:** 14 days of automated backups with point-in-time restore. No `pg_dump` cron job.
- **Logs:** Docker keeps 5 × 20 MB per container (`bin/production logs`). RDS sends PostgreSQL's logs, including queries slower than 500 ms, to CloudWatch Logs at `/aws/rds/instance/wisp-prod/postgresql`.

### Routine deploys

Push the commit to GitHub, then from your machine:

```bash
bin/production deploy          # builds and deploys HEAD (or: bin/production deploy <commit>)
```

On the server, `deploy`:
1. Checks `.env` has the required settings.
2. Fetches the repo, checks out the commit and builds its image, tagged `wisp3:<commit>` (a few minutes; Docker's cache skips the gem and pnpm installs when the lockfiles haven't changed). A commit already built is reused.
3. Points `wisp3:deployed`, the image the compose file runs, at it.
4. Runs `db:prepare db:seed` (migrations, then the reference data) with the new image. If that fails, `wisp3:deployed` goes back to the previous image and the running site is untouched.
5. Replaces the containers. The site is down for a few seconds while `web` restarts.
6. Keeps the newest 5 images and a week of build cache.

Other commands:

```bash
bin/production status          # containers and /up (its version is the deployed commit)
bin/production images          # images on the server, newest first
bin/production logs web        # follow logs (web, jobs, or both)
bin/production console         # Rails console
bin/production rails runner 'puts User.count'
bin/production ssh             # a shell in /opt/wisp
```

**Rolling back:** `bin/production deploy <earlier commit>`. It reuses that image if it's still on the server (`bin/production images`), or builds it again. Migrations aren't rolled back, so a rollback past a migration needs that migration to be backward compatible.

**Changing a setting or secret:** edit `/opt/wisp/.env` on the server, then `docker compose up -d --force-recreate` in `/opt/wisp` so the containers read it. Update the password manager too.

### First-time setup

#### 1. Check the server (once)

```bash
ssh wisp-prod                      # Host wisp-prod in ~/.ssh/config: HostName 54.159.70.187, your user and key
docker compose version             # Docker with the Compose plugin
docker ps                          # works without sudo (you're in the docker group)
git --version
free -h                            # memory, for the build (below)
sudo mkdir -p /opt/wisp && sudo chown "$USER": /opt/wisp
```

If `docker ps` says permission denied, run `sudo usermod -aG docker "$USER"` and log in again. If Docker isn't installed, install it with Docker's apt repository (docs.docker.com, "Install Docker Engine on Ubuntu").

The t3.medium has 4 GB of memory, which the build shares with the running site. If a build dies with exit code 137 (out of memory, most likely in the Vite build), add swap once:

```bash
sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

#### 2. The database role and databases (done)

The app connects as `wisp3`, not the admin user `wisp_admin`, whose password IT sent separately. `wisp_admin` stays out of the app and its `.env`.

On the server, download the RDS certificate bundle once (`curl -o ~/global-bundle.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem`), then connect as `wisp_admin`:

```bash
export RDSHOST=wisp-prod.chjgrhbg1z6x.us-east-1.rds.amazonaws.com
psql "host=$RDSHOST port=5432 dbname=postgres user=wisp_admin sslmode=verify-full sslrootcert=$HOME/global-bundle.pem"
```

Generate the `wisp3` password with `openssl rand -base64 32 | tr -d '/+='` and keep it in the password manager. Then:

```sql
CREATE ROLE wisp3 LOGIN;
\password wisp3
GRANT wisp3 TO wisp_admin;   -- PG 16+: lets wisp_admin create databases owned by wisp3

CREATE DATABASE wisp3_production       OWNER wisp3;
CREATE DATABASE wisp3_production_cache OWNER wisp3;
CREATE DATABASE wisp3_production_queue OWNER wisp3;

REVOKE CONNECT ON DATABASE wisp3_production, wisp3_production_cache, wisp3_production_queue FROM PUBLIC;
```

`\password` sends only a hash, so the password stays out of logs and shell history. Check the role with `psql "host=$RDSHOST dbname=wisp3_production user=wisp3 sslmode=verify-full sslrootcert=$HOME/global-bundle.pem" -c 'select current_user'`. The first deploy creates the tables. `wisp3` owns its databases, so it can enable `btree_gist`, a trusted extension on RDS.


#### 3. The settings file

On the server, create `/opt/wisp/.env` readable only by you, and fill it in with an editor, so no secret goes through shell history:

```bash
cd /opt/wisp && touch .env && chmod 600 .env && nano .env
```

One `NAME='value'` per line. Single quotes keep Compose from reading `$` or `#` in a value, so a value can't contain a single quote itself.

```bash
RAILS_MASTER_KEY='…'               # contents of config/credentials/production.key (password manager)
WISP3_DATABASE_PASSWORD='…'        # the wisp3 password from step 2
DB_HOST='wisp-prod.chjgrhbg1z6x.us-east-1.rds.amazonaws.com'
APP_HOST='…'                       # the public hostname (step 5)
OPEN_METEO_API_KEY='…'             # optional; without it the free API is used
# Mail (step 4)
SMTP_ADDRESS='…'
SMTP_PORT='587'
SMTP_USERNAME='…'                  # leave both out if the relay admits the server by its IP
SMTP_PASSWORD='…'
# MAILER_FROM='WISP <agweather@cals.wisc.edu>'   # the default
```

The deploy refuses to run without the first four. `DB_PORT` defaults to 5432. `RAILS_MASTER_KEY` decrypts `config/credentials/production.yml.enc`, which holds only `secret_key_base`.

#### 4. Mail (the CALS SMTP relay)

The app sends through any SMTP relay set by `SMTP_*`; nothing in the code is specific to one. Ask CALS IT:

- **The relay's hostname and port.** It has to be 587 (STARTTLS) or 465 (TLS from the start; set `SMTP_PORT='465'`). EC2 blocks outbound port 25, so a relay only on 25 won't work from this server.
- **How it admits the server:** a username and password (`SMTP_USERNAME`, `SMTP_PASSWORD`), or by IP address, in which case ask them to allow 54.159.70.187 and leave both out.
- **That it may send as `agweather@cals.wisc.edu`** (or the address in `MAILER_FROM`), and that it signs with DKIM or is in `cals.wisc.edu`'s SPF record, so the mail passes wisc.edu's DMARC check instead of landing in spam.

Then, once the app is deployed (step 6), send yourself a message:

```bash
bin/production rails runner 'ActionMailer::Base.mail(from: Rails.configuration.x.mailer_from, to: "you@wisc.edu", subject: "WISP test", body: "Mail works").deliver_now'
```

A timeout means the server can't reach the relay (the port, or a firewall on either side); `535` means the username or password; `550` or `554` usually means the relay won't send for this server or sender. Check that the test arrived in the inbox, not spam, and that its headers show `dkim=pass` or `spf=pass`. Until mail works, production can't send sign-up confirmations or sign-in links.

#### 5. DNS and the firewall

Before the first deploy, ask IT (and campus DNS) for:
- **A DNS record:** `APP_HOST` resolving to 54.159.70.187. `wisp.cals.wisc.edu` still serves legacy until launch (PLAN.md §13), so start with a temporary name.
- **Inbound 80 and 443** from anywhere in the server's security group. Let's Encrypt checks port 80, and browsers use 443.

Thruster asks Let's Encrypt for the certificate on the first HTTPS request. If DNS or the ports aren't ready, HTTPS fails until they are.

#### 6. Deploy and verify

Push `main` to GitHub, then:

```bash
bin/production deploy              # the first build takes longest: nothing is cached yet
bin/production status
```

- `https://<APP_HOST>/up` returns 200 with JSON, with `database` `ok` and `version` the deployed commit. `status` reads `degraded` until the first morning health check (7 am), which is expected.
- Make yourself an admin: `bin/production rails runner 'User.find_by!(email: "you@…").update!(admin: true)'`.
- Once mail is set up, sign up, receive the confirmation, and sign in with both a password and an emailed link.
- After the 5 am, 11 am or 5 pm refresh, `/admin/weather` shows weather for every active cell.
