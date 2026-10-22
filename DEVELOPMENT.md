# Development

How to set up a machine to work on WISP 3, the day-to-day commands, and how deployment fits in. The conventions for writing code here (tenancy, units, the engine, gotchas) are in [CLAUDE.md](CLAUDE.md); the design and roadmap are in [PLAN.md](PLAN.md).

## 1. Prerequisites

Written for Ubuntu 24.04, natively or under WSL2 on Windows. macOS works too with the Homebrew equivalents.

| Tool | Version | Why |
|---|---|---|
| Ruby | 4.0.5 (`.ruby-version`), through rbenv | The app |
| Node.js | 24 (`.node-version`) | Vite builds and the frontend tests |
| pnpm | from `packageManager` in `package.json`, through corepack | JavaScript packages |
| PostgreSQL | 16 or newer | The database (CI uses 16; 18 works) |
| Chromium for Playwright | installed by Playwright | The browser tests (`bin/e2e`) |

### System packages

```bash
sudo apt update
sudo apt install -y build-essential git curl libssl-dev libyaml-dev zlib1g-dev libffi-dev libgmp-dev \
  libreadline-dev libpq-dev rustc
```

`rustc` is optional in development. With it, ruby-build includes YJIT, Ruby's JIT, which Rails turns on in production. Install it on servers so production gets YJIT (PLAN.md §12). In development it only makes the app a bit faster.

### Ruby

```bash
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
echo 'eval "$(~/.rbenv/bin/rbenv init - bash)"' >> ~/.bashrc && exec bash
rbenv install 4.0.5
```

Check YJIT with `ruby --yjit -e 'p RubyVM::YJIT.enabled?'`, which prints `true` if Ruby was built with it. To add YJIT to a Ruby built without it, install `rustc`, then run `rbenv install --force 4.0.5` followed by `bundle install` (the reinstall removes its gems).

### Node and pnpm

Install Node 24 with any version manager (fnm, nvm) or NodeSource's packages, then turn on corepack so the pinned pnpm is used:

```bash
corepack enable
pnpm --version     # matches packageManager in package.json
```

### PostgreSQL

Install it from Ubuntu or the PostgreSQL apt repository. In development the app connects to `localhost:5432` as `postgres` with the password `password`; set `DB_HOST`, `DB_PORT`, `DB_USER` or `DB_PWD` to use something else.

```bash
sudo apt install -y postgresql
sudo service postgresql start        # WSL doesn't start services on boot
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'password';"
```

## 2. The app

```bash
git clone https://github.com/uwent/wisp3.git && cd wisp3
cp .env.example .env                                   # OPEN_METEO_API_KEY may stay blank (free API)
bin/setup --skip-server                                # gems, pnpm packages (and the git hook), databases
pnpm exec playwright install --with-deps chromium      # the browser for bin/e2e
bin/dev                                                # http://localhost:3000
```

`bin/setup` runs `db:prepare`, which creates the development and test databases and loads the reference data (crops, soil types, canopy curves from `db/reference/`). `pnpm install` installs a Husky pre-commit hook that runs ESLint and Prettier on staged files (lint-staged).

### Data to work with

- **A demo account:** `bin/rails demo:seed` builds farms, pivots, fields and a season of entries, and prints the sign-in. It takes `EMAIL=`, `PASSWORD=` and `YEAR=`.
- **Weather:** in development, jobs run inside the web server (Active Job's async adapter). Creating a pivot queues its weather backfill from Open-Meteo, which needs network access. `bin/rails weather:refresh` fetches weather for every active cell now.
- **Email:** mail opens in the browser at http://localhost:3000/letter_opener, so you can sign up and use sign-in links without a mail server.
- **An admin:** `bin/rails runner 'User.find_by!(email: "you@example.com").update!(admin: true)'` opens the admin pages (users, weather status, health check).

## 3. Day to day

```bash
bin/dev                                   # Rails on :3000 and the Vite dev server
bin/ci                                    # everything CI runs (below)
bundle exec rspec spec/path_spec.rb       # one Rails spec file
pnpm test                                 # Vitest (frontend logic and components)
pnpm check                                # svelte-check and TypeScript
bin/e2e                                   # Playwright, on its own database (wisp3_e2e); args go to playwright test
bin/e2e keyboard.spec.ts --project desktop
bundle exec standardrb --fix              # Ruby style
bin/rails typelizer:generate              # after changing serializers or routes; commit the output
```

`bin/ci` runs, in order: Ruby style (Standard), frontend style and lint (Prettier, ESLint), type checks, whether the generated TypeScript types and route helpers are current, Vitest, RSpec, then the Playwright suite. The browser tests include an accessibility scan of every page (axe), keyboard tests, and checks that pages reflow at 320 px wide and with 200% text. GitHub Actions runs the same script on every push to `main` and on pull requests (`.github/workflows/ci.yml`).

The specs never use the network: Open-Meteo responses are recorded in `spec/fixtures/files/open_meteo`, and WebMock blocks the rest.

### Other tasks

```bash
bin/rails weather:compare      # AgWeather vs Open-Meteo report → docs/weather-comparison.md
bin/rails demo:seed            # rebuild the demo account
```

## 4. Secrets and credentials

| Environment | Where secrets live |
|---|---|
| development, test | `.env` (gitignored), read by dotenv; only `OPEN_METEO_API_KEY`, which is optional |
| staging | `config/credentials/staging.yml.enc`, decrypted by `config/credentials/staging.key` |
| production | `config/credentials/production.yml.enc` and `production.key`, to be created for the new server |

Keys are never committed. Keep each in the team's password manager. A server gets its key copied to `~/wisp3/shared/config/credentials/` (docs/deployment.md, step 3).

The credentials hold `database.password` (the `wisp3` Postgres role) and, optionally, `open_meteo.api_key`. To create production's:

```bash
bin/rails credentials:edit --environment production    # writes production.yml.enc and production.key
```

```yaml
database:
  password: <a long random password; the same one goes into CREATE ROLE on the server>
open_meteo:
  api_key: <optional: the commercial key; without it the free endpoints are used>
```

Commit `production.yml.enc`, store `production.key` in the password manager, and copy it to the server.

## 5. Deployment

Capistrano deploys `main` (or `BRANCH=…`) to each server, where Puma and the Solid Queue worker run as systemd user services owned by `deploy`. Each deploy installs packages, builds the Vite assets, runs migrations and restarts both services.

```bash
cap staging deploy
cap staging systemd:status
PRODUCTION_HOST=<hostname> cap production deploy     # once the new server exists
```

- **Routine deploys, first-time server setup** (database role, credentials key, services, nginx) **and verifying a deploy:** [docs/deployment.md](docs/deployment.md).
- **What the new production server needs** (packages including `rustc`, the `deploy` user with linger, network, TLS, mail, backups): PLAN.md §12.
- **After a deploy,** `https://<host>/up` returns JSON with `status` (`ok`, `degraded` or `down`), the deployed `version` and the morning health check's result. An uptime monitor can watch it.

## 6. Troubleshooting

- **`PG::ConnectionBad` in WSL:** Postgres isn't running. Start it with `sudo service postgresql start`.
- **Vite assets missing or stale in tests:** `bin/e2e` builds them; for RSpec request specs nothing is needed. In development `bin/dev` serves them.
- **Playwright can't launch Chromium:** rerun `pnpm exec playwright install --with-deps chromium`. The `--with-deps` part needs sudo for the system libraries.
- **Stopping a dev server:** stop it by port or PID (`lsof -i :3000`). `pkill -f` with a pattern that also matches your own command line kills the shell running it.
- **`systemctl --user` over SSH says "Failed to connect to bus":** set `XDG_RUNTIME_DIR=/run/user/$(id -u)` first. Capistrano's tasks do this.
- **CI says generated types or routes are out of date:** run `bin/rails typelizer:generate` and commit the changes.
