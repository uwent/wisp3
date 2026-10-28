# Deployment

| Stage | Where | How | URL | Rails env |
|---|---|---|---|---|
| staging | `dev.agweather.cals.wisc.edu` (SSH port 216), local Postgres | Capistrano, systemd user services | https://dev.wisp.cals.wisc.edu | `staging` |
| production | AWS us-east-1: EC2 `wisp-prod` (54.159.70.187), RDS `wisp-prod` (PostgreSQL 18) | Docker Compose, images in ECR | https://wisp.cals.wisc.edu (at launch) | `production` |

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

The AWS resources were set up by Eric Dieckman (CALS IT). Each deploy ships one image, tagged with its commit, built from the [Dockerfile](../Dockerfile) and stored in ECR. On the server, [config/deploy/compose.production.yaml](../config/deploy/compose.production.yaml) (copied to `/opt/wisp/compose.yaml`) runs it as two containers:

- `web`: Thruster on ports 80 and 443 in front of Puma. Thruster gets and renews the Let's Encrypt certificate for `APP_HOST` by itself, so there's no nginx or certbot.
- `jobs`: the Solid Queue worker (`bin/jobs`).

| Resource | Name | Address or ID |
|---|---|---|
| App server (EC2, Ubuntu 26.04, t3.medium) | `wisp-prod` | 54.159.70.187 (Elastic IP); you log in as yourself with an SSH key |
| Database (RDS PostgreSQL 18) | `wisp-prod` | `wisp-prod.chjgrhbg1z6x.us-east-1.rds.amazonaws.com:5432` |
| Image registry (ECR) | `wisp3` | `702627367783.dkr.ecr.us-east-1.amazonaws.com/wisp3` |
| Settings and secrets (SSM Parameter Store) | `/wisp/prod/*` | us-east-1 |

- **The database is only reachable from the server** (private subnets; its security group admits the server's). It requires TLS, and the app checks RDS's certificate against [config/rds-global-bundle.pem](../config/rds-global-bundle.pem), which is in the image.
- **SSH (port 22) is open only to the IP addresses Eric has on file.** If a connection times out from a new place (home, campus, VPN), send him your public IP.
- **Secrets never go in the image or the repo.** Each deploy writes `/opt/wisp/.env` from SSM, readable only by its owner.
- **Backups are RDS's:** 14 days of automated backups with point-in-time restore. No `pg_dump` cron job.
- **Logs:** Docker keeps 5 × 20 MB per container (`bin/production logs`). RDS sends PostgreSQL's logs, including queries slower than 500 ms, to CloudWatch Logs at `/aws/rds/instance/wisp-prod/postgresql`.
- **Tag anything you create in AWS** with `project=agweather`, `app=wisp` and `env=prod`.

### Routine deploys

From your machine, on a committed `main`:

```bash
bin/production push            # builds HEAD's image for linux/amd64 and pushes it to ECR
bin/production deploy          # deploys HEAD's image
```

`deploy` copies the compose file to the server, then:
1. Rewrites `.env` from SSM, adding `TAG`, the image to run.
2. Pulls the image.
3. Runs `db:prepare db:seed` (migrations, then the reference data).
4. Replaces the containers. The site is down for a few seconds while `web` restarts.
5. Prunes images older than a week.

Other commands:

```bash
bin/production status          # containers, the deployed tag and /up
bin/production logs web        # follow logs (web, jobs, or both)
bin/production console         # Rails console
bin/production rails runner 'puts User.count'
bin/production ssh             # a shell in /opt/wisp
```

**Rolling back:** `bin/production deploy <earlier tag>`, where `aws ecr list-images --repository-name wisp3` lists the tags. Migrations aren't rolled back, so a rollback past a migration needs that migration to be backward compatible. ECR keeps the newest 30 tagged images, and tags can't be overwritten.

**Changing a setting or secret:** update it in SSM (see step 3 below, with `--overwrite`), then run `bin/production deploy` with the current tag. Every deploy rewrites `.env`.

### First-time setup

#### 1. AWS access from your machine

You sign in through UW–Madison's SSO link. For the CLI, use the profile that SSO gives you:
- **The link lands on an AWS access portal** (`….awsapps.com/start`): run `aws configure sso` once, then `aws sso login` before a session.
- **It goes straight to the console:** use `aws login`. Your role needs the `SignInLocalDevelopmentAccess` permissions for this.

Then `export AWS_PROFILE=<profile>` and check with `aws sts get-caller-identity` (account 702627367783). CloudShell in the console also works for the SSM steps.

Your role needs:
- `ssm:PutParameter` and `ssm:GetParametersByPath` on `/wisp/prod/*`, and KMS use of the SSM key, for SecureString values.
- Push access to the `wisp3` ECR repository.

The server's instance role needs:
- `ssm:GetParametersByPath` on `/wisp/prod/` and `kms:Decrypt`.
- Pull access to ECR.

Eric sets these up.

#### 2. The database role and databases (done)

The app connects as `wisp3`, not the admin user `wisp_admin`, whose password Eric sent separately. `wisp_admin` stays out of the app and SSM.

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

#### 3. SSM parameters

One parameter per environment variable, named `/wisp/prod/<VARIABLE>`. Secrets are `SecureString`. Values can't contain a single quote.

| Parameter | Type | Value |
|---|---|---|
| `RAILS_MASTER_KEY` | SecureString | contents of `config/credentials/production.key` (from the password manager). It decrypts `config/credentials/production.yml.enc`, which holds only `secret_key_base` |
| `WISP3_DATABASE_PASSWORD` | SecureString | the `wisp3` password from step 2 |
| `OPEN_METEO_API_KEY` | SecureString | the commercial Open-Meteo key (optional; without it the free API is used) |
| `DB_HOST` | String | `wisp-prod.chjgrhbg1z6x.us-east-1.rds.amazonaws.com` |
| `APP_HOST` | String | the public hostname (DNS must point at 54.159.70.187; step 4) |
| `MAILER_FROM` | String | optional; defaults to `WISP <agweather@cals.wisc.edu>` |
| `SMTP_ADDRESS`, `SMTP_PORT` | String | the mail relay, once decided (SES or campus, port 587; EC2 blocks 25). Until it's set, production can't send mail, which includes sign-up confirmations |
| `SMTP_USERNAME`, `SMTP_PASSWORD` | SecureString | the relay's credentials, if it needs them |

`DB_PORT` defaults to 5432. Create each one like this; `read -s` keeps the value off the screen and out of shell history:

```bash
read -rs VALUE   # paste, then Enter
aws ssm put-parameter --region us-east-1 --name /wisp/prod/WISP3_DATABASE_PASSWORD \
  --type SecureString --value "$VALUE" \
  --tags Key=project,Value=agweather Key=app,Value=wisp Key=env,Value=prod
unset VALUE
```

For the master key: `--value "$(cat config/credentials/production.key)"`. For plain values: `--type String --value …`. To change a value, add `--overwrite` and leave out `--tags`, because the two can't be combined.

#### 4. DNS and the firewall

Before the first deploy, ask Eric (and campus DNS) for:
- **A DNS record:** `APP_HOST` resolving to 54.159.70.187. `wisp.cals.wisc.edu` still serves legacy until launch (PLAN.md §13), so start with a temporary name.
- **Inbound 80 and 443** from anywhere in the server's security group. Let's Encrypt checks port 80, and browsers use 443.

Thruster asks Let's Encrypt for the certificate on the first HTTPS request. If DNS or the ports aren't ready, HTTPS fails until they are.

#### 5. Prepare the server (once)

```bash
ssh wisp-prod                    # Host wisp-prod in ~/.ssh/config: HostName 54.159.70.187, your user and key

sudo snap install aws-cli --classic
sudo apt install -y amazon-ecr-credential-helper
mkdir -p ~/.docker
echo '{ "credHelpers": { "702627367783.dkr.ecr.us-east-1.amazonaws.com": "ecr-login" } }' > ~/.docker/config.json
sudo mkdir -p /opt/wisp && sudo chown "$USER": /opt/wisp

aws ssm get-parameters-by-path --region us-east-1 --path /wisp/prod/ --query 'Parameters[*].Name'   # the instance role can read SSM
```

The credential helper logs Docker in to ECR with the instance role, so pulls never need a password.

#### 6. Push, deploy and verify

```bash
bin/production push
bin/production deploy
bin/production status
```

- `https://<APP_HOST>/up` returns 200 with JSON, with `database` `ok` and `version` the deployed commit. `status` reads `degraded` until the first morning health check (7 am), which is expected.
- Make yourself an admin: `bin/production rails runner 'User.find_by!(email: "you@…").update!(admin: true)'`.
- Once mail is set up, sign up, receive the confirmation, and sign in with both a password and an emailed link.
- After the 5 am, 11 am or 5 pm refresh, `/admin/weather` shows weather for every active cell.

### Before GitHub Actions deploys

Images are built and pushed from your machine for now. Once Eric sets up an OIDC role for `uwent/wisp3`, a workflow can run `bin/production push` after CI passes on `main`.
