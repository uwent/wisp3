# Deployment

| Stage | Where | How | URL | Rails env |
|---|---|---|---|---|
| staging | `dev.agweather.cals.wisc.edu` (SSH port 216), local Postgres | Capistrano, systemd user services | https://dev.wisp.cals.wisc.edu | `staging` |
| production | AWS us-east-1: EC2 `wisp-prod` (54.159.70.187), RDS `wisp-prod` (PostgreSQL 18) | Docker Compose, images built on the server | https://54-159-70-187.sslip.io for now; https://wisp.cals.wisc.edu at launch | `production` |

Both run the same two processes: the web server (Puma) and the Solid Queue worker (weather refresh, the daily digest, the health check and other background jobs).

- [Staging](#staging-capistrano)
- [Production](#production-docker-on-ec2)

---

## Staging (Capistrano)

On the staging host WISP 3 runs as two **systemd user services** owned by `deploy`, so deploys restart them without sudo:

- `wisp3-web`: Puma on `127.0.0.1:3100`, behind nginx
- `wisp3-jobs`: the Solid Queue worker

The staging host also runs ag-weather and the legacy WISP staging app. WISP 3 takes over the `dev.wisp.cals.wisc.edu` site; legacy files in `~/wisp` are left alone.

For SSH and `scp`, add the host to `~/.ssh/config` on your machine (Capistrano has its own settings in `config/deploy/staging.rb` and doesn't need this):

```
Host agwx-dev
  HostName dev.agweather.cals.wisc.edu
  User deploy
  Port 216
```

### Routine deploys

```bash
cap staging deploy                 # deploys main; BRANCH=some-branch cap staging deploy for others
cap staging systemd:status         # service status
ssh agwx-dev journalctl --user -u wisp3-web -f     # logs (also wisp3-jobs)
```

Each deploy installs pnpm packages, builds the Vite assets, runs `db:prepare` (migrations), loads the reference data and restarts both services.

### First-time setup

Done once, in October 2026; kept for rebuilding the server.

#### 1. Check the prerequisites (as `deploy`)

```bash
ssh agwx-dev
rbenv versions                                   # needs 4.0.5 (rbenv install 4.0.5 if missing)
node -v                                          # needs v24.x on the non-interactive PATH, see below
loginctl show-user deploy --property=Linger      # needs Linger=yes (already confirmed on staging)
```

Capistrano runs commands in a non-interactive shell. If `ssh agwx-dev 'node -v'` fails but `node -v` works after logging in, Node is only on the interactive PATH. Install it system-wide, or add its `bin` directory to `default_env[:PATH]` in `config/deploy/staging.rb`.

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
ssh agwx-dev 'mkdir -p ~/wisp3/shared/config/credentials'
scp config/credentials/staging.key agwx-dev:wisp3/shared/config/credentials/
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

CALS IT set up the server and the database; nothing else in AWS is used, so nothing here needs AWS permissions. Each deploy builds the commit's image on the server from a git checkout of the public repo and the [Dockerfile](../Dockerfile), and [config/deploy/compose.production.yaml](../config/deploy/compose.production.yaml) runs it as two containers:

- `web`: Thruster on ports 80 and 443 in front of Puma. Thruster gets and renews the Let's Encrypt certificate for `APP_HOST` by itself, so there's no nginx or certbot.
- `jobs`: the Solid Queue worker (`bin/jobs`).

| Resource | Name | Address |
|---|---|---|
| App server (EC2, Ubuntu 26.04, t3.medium: 2 vCPUs, 4 GB, 38 GB disk) | `wisp-prod` | 54.159.70.187 (Elastic IP); you log in as yourself with an SSH key |
| Database (RDS PostgreSQL 18) | `wisp-prod` | `wisp-prod.chjgrhbg1z6x.us-east-1.rds.amazonaws.com:5432` |
| Site | | `https://54-159-70-187.sslip.io` until campus DNS gives it a name (step 3) |

On the server, everything is in `/opt/wisp`, owned by you:

| Path | What |
|---|---|
| `.env` | Settings and secrets, edited by hand (step 4), readable only by you |
| `src/` | A clone of `github.com/uwent/wisp3`, checked out by each deploy at the commit it builds. Don't edit it |
| `compose.yaml` | The deployed commit's compose file, copied by each deploy |

- **The database is only reachable from the server** (private subnets; its security group admits the server's). It requires TLS, and the app checks RDS's certificate against [config/rds-global-bundle.pem](../config/rds-global-bundle.pem), which is in the image.
- **SSH (port 22) is open only to the IP addresses IT has on file.** If a connection times out from a new place (home, campus, VPN), send IT your public IP.
- **Secrets never go in the image or the repo.** They're only in `/opt/wisp/.env` and the password manager, so keep the password manager's copy current.
- **Backups are RDS's:** 14 days of automated backups with point-in-time restore. No `pg_dump` cron job.
- **Reboots:** Docker starts at boot and the containers are `restart: unless-stopped`, so the site comes back by itself.
- **Logs:** Docker keeps 5 × 20 MB per container (`bin/production logs`). RDS sends PostgreSQL's logs, including queries slower than 500 ms, to CloudWatch Logs at `/aws/rds/instance/wisp-prod/postgresql`.

`bin/production` runs everything over SSH to the host `wisp-prod`, so add it to `~/.ssh/config` on your machine:

```
Host wisp-prod
  HostName 54.159.70.187
  User <your server username>
  IdentityFile ~/.ssh/<your key>
```

### Routine deploys

Push the commit to GitHub (any branch), then from your machine:

```bash
bin/production deploy          # builds and deploys HEAD (or: bin/production deploy <commit>)
```

On the server, `deploy`:
1. Checks `.env` has the required settings.
2. Fetches the repo, checks out the commit and builds its image, tagged `wisp3:<commit>`. Docker's cache skips the gem and pnpm installs when the lockfiles haven't changed, so most builds take a few minutes. A commit already built is reused.
3. Points `wisp3:deployed`, the image the compose file runs, at it.
4. Runs `db:prepare db:seed` (migrations, then the reference data) with the new image. If that fails, `wisp3:deployed` goes back to the previous image and the running site is untouched.
5. Replaces the containers. The site is down for a few seconds while `web` restarts.
6. Keeps the newest 5 images and a week of build cache.

Then check it with `bin/production status`: both containers up, `web` "healthy" after about 30 seconds, and `/up`'s `version` the commit you deployed.

**Rolling back:** `bin/production deploy <earlier commit>`. It reuses that image if it's still on the server (`bin/production images`), or builds it again. Migrations aren't rolled back, so a rollback past a migration needs that migration to be backward compatible.

**Changing a setting or secret:** edit `/opt/wisp/.env` on the server (`bin/production ssh`, then `nano .env`), then `docker compose up -d --force-recreate` in `/opt/wisp` so the containers read it. Update the password manager too. `APP_HOST` is covered in step 3.

### Other commands

```bash
bin/production status          # containers and /up (its version is the deployed commit)
bin/production images          # images on the server, newest first
bin/production logs web        # follow logs (web, jobs, or both)
bin/production console         # Rails console
bin/production rails runner 'puts User.count'
bin/production rails weather:refresh      # any bin/rails command or task
bin/production ssh             # a shell in /opt/wisp
```

On the server, in `/opt/wisp`, Compose works directly: `docker compose restart web`, `docker compose ps -a`. For a database shell, the image has no `psql`, but the server does:

```bash
psql "host=wisp-prod.chjgrhbg1z6x.us-east-1.rds.amazonaws.com dbname=wisp3_production user=wisp3 sslmode=verify-full sslrootcert=$HOME/global-bundle.pem"
```

It asks for the `wisp3` password (in `.env` and the password manager).

### Troubleshooting

- **The deploy fails:** its output names the step. `.env has no …` is a missing setting (step 4); `isn't on GitHub` means push first; a build killed with exit code 137 ran out of memory (step 1, swap). A failed migration leaves the old version running; fix it and deploy again.
- **`web` isn't running or isn't healthy:** `docker compose ps -a` on the server shows each container's state and exit code, and `bin/production logs web` the error. Rails refusing to boot is usually a setting: a wrong `RAILS_MASTER_KEY` (`ActiveSupport::MessageEncryptor::InvalidMessage`), or the database password or host (`PG::ConnectionBad`). If there are no containers at all, `docker events --since 1h --filter type=container` shows what was created and when it exited.
- **HTTPS fails:** Thruster asks Let's Encrypt for the certificate on the first HTTPS request, which needs `APP_HOST` to resolve to 54.159.70.187 publicly and ports 80 and 443 open (step 3). `bin/production logs web` shows the certificate errors, including Let's Encrypt's rate limits.
- **A page is a blank 403:** the request was addressed to a name other than `APP_HOST`, such as the bare IP address. Rails answers only that name (`/up` excepted).
- **The disk fills:** `docker system df` shows what Docker holds; `docker builder prune -af` clears the build cache (the next build is slower).

### First-time setup

In order, the first time and when rebuilding the server.

#### 1. Check the server

```bash
ssh wisp-prod
docker compose version             # Docker with the Compose plugin
docker ps                          # works without sudo (you're in the docker group)
git --version
sudo mkdir -p /opt/wisp && sudo chown "$USER": /opt/wisp
```

Run the `chown` straight after the `mkdir`: if root owns `/opt/wisp`, you can't create `.env` or let the deploy write there without sudo, and a `.env` written with sudo is unreadable without it too. To fix that later, `sudo chown -R "$USER": /opt/wisp`.

If `docker ps` says permission denied, run `sudo usermod -aG docker "$USER"` and log in again. If Docker isn't installed, install it with Docker's apt repository (docs.docker.com, "Install Docker Engine on Ubuntu").

The build shares the server's 4 GB with the running site; the first builds fit without swap. If one dies with exit code 137 (out of memory, most likely in the Vite build), add swap once:

```bash
sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

#### 2. The database role and databases (done, October 2026)

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


#### 3. DNS and the firewall

Ask IT (and campus DNS) for these early, as they take longest:
- **Inbound 80 and 443** from anywhere in the server's security group. Let's Encrypt checks port 80, and browsers use 443.
- **A DNS record:** the hostname resolving to 54.159.70.187. `wisp.cals.wisc.edu` still serves legacy until launch (PLAN.md §13), so start with a temporary name.

Until the record exists, use `54-159-70-187.sslip.io` as `APP_HOST`. sslip.io is a public DNS service that resolves any name with an IP address in it to that address, so Let's Encrypt can issue a real certificate for it. If its certificate hits Let's Encrypt's rate limits (many people use sslip.io), `54.159.70.187.nip.io` works the same way.

**Changing `APP_HOST`** (to the temporary name, then at launch): edit it in `.env` and `docker compose up -d --force-recreate`. Thruster gets a certificate for the new name on its first request. Everyone is signed out, since sessions belong to the old name, and links in emails already sent point to the old name.

#### 4. The settings file

On the server, create `/opt/wisp/.env` readable only by you, and fill it in with an editor, so no secret goes through shell history:

```bash
cd /opt/wisp && touch .env && chmod 600 .env && nano .env
```

One `NAME='value'` per line. Single quotes keep Compose from reading `$` or `#` in a value, so a value can't contain a single quote itself. Lines starting with `#` are comments.

```bash
RAILS_MASTER_KEY='…'               # contents of config/credentials/production.key (password manager)
WISP3_DATABASE_PASSWORD='…'        # the wisp3 password from step 2
DB_HOST='wisp-prod.chjgrhbg1z6x.us-east-1.rds.amazonaws.com'
APP_HOST='54-159-70-187.sslip.io'  # the public hostname (step 3)
OPEN_METEO_API_KEY='…'             # optional; without it the free API is used
# Mail (step 7); until SMTP_ADDRESS is set, production can't send mail
SMTP_ADDRESS='…'
SMTP_PORT='587'
SMTP_USERNAME='…'                  # leave both out if the relay admits the server by its IP
SMTP_PASSWORD='…'
# MAILER_FROM='WISP <agweather@cals.wisc.edu>'   # the default
```

The deploy refuses to run without the first four. `DB_PORT` defaults to 5432. `RAILS_MASTER_KEY` decrypts `config/credentials/production.yml.enc`, which holds only `secret_key_base`. Save a copy of the finished file in the password manager.

#### 5. Deploy and verify

Push the branch to GitHub, then:

```bash
bin/production deploy              # the first build takes longest: nothing is cached yet
bin/production status
```

- `status` shows `web` (healthy) and `jobs` up.
- `https://<APP_HOST>/up` returns 200 with JSON, with `database` `ok` and `version` the deployed commit. Its `status` reads `degraded` until the first morning health check (7 am), which is expected. The first request takes a few seconds while Thruster gets the certificate.
- The landing page and `/about` load with their styles (the Vite assets are in the image).

#### 6. The first admin

Signing up sends a confirmation email, which can't happen until mail works (step 7), so create the first admin account in the Rails console instead, already confirmed:

```bash
bin/production console
```

```ruby
password = IO.console.getpass("Password: ")       # typed without echo, so it isn't on screen or in the history
user = User.new(email: "you@wisc.edu", first_name: "…", last_name: "…", password:, admin: true)
user.skip_confirmation!
user.save!
```

Passwords are 8 to 128 characters. Sign in at `https://<APP_HOST>` with the password; the menu gains the admin pages (Weather, Users). Like every account, it starts with an empty operation of its own.

To make an existing account an admin (for example someone who has signed up since mail started working):

```bash
bin/production rails runner 'User.find_by!(email: "them@…").update!(admin: true)'
```

Admins see every account (`/admin/users`, where they can also sign in as someone to help them), and the morning health check emails them when something's wrong, so keep the list short.

#### 7. Mail (the CALS SMTP relay)

The app sends through any SMTP relay set by `SMTP_*`; nothing in the code is specific to one. Ask CALS IT:

- **The relay's hostname and port.** It has to be 587 (STARTTLS) or 465 (TLS from the start; set `SMTP_PORT='465'`). EC2 blocks outbound port 25, so a relay only on 25 won't work from this server.
- **How it admits the server:** a username and password (`SMTP_USERNAME`, `SMTP_PASSWORD`), or by IP address, in which case ask them to allow 54.159.70.187 and leave both out.
- **That it may send as `agweather@cals.wisc.edu`** (or the address in `MAILER_FROM`), and that it signs with DKIM or is in `cals.wisc.edu`'s SPF record, so the mail passes wisc.edu's DMARC check instead of landing in spam.

Put the settings in `.env`, `docker compose up -d --force-recreate`, then send yourself a message:

```bash
bin/production rails runner 'ActionMailer::Base.mail(from: Rails.configuration.x.mailer_from, to: "you@wisc.edu", subject: "WISP test", body: "Mail works").deliver_now'
```

A timeout means the server can't reach the relay (the port, or a firewall on either side); `535` means the username or password; `550` or `554` usually means the relay won't send for this server or sender. Check that the test arrived in the inbox, not spam, and that its headers show `dkim=pass` or `spf=pass`.

Then check the app's own mail: sign up with a second address and receive the confirmation, sign in with an emailed link and code, and send a test digest from the Alerts page.

#### 8. After the first day

- After the 5 am, 11 am or 5 pm (Central) weather refresh, `/admin/weather` shows weather for every active cell.
- After 7 am, `/up` reads `ok`, and the admin weather page shows the health check's result. An uptime monitor can alert on a non-200 response or on `"status":"degraded"`.
- Before launch, restore an RDS snapshot to a scratch instance once and check the app against it (IT may need to do this).
