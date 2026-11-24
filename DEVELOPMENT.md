# Development

How to set up a machine to work on WISP 3, the day-to-day commands, and how deployment fits in.

Other documents:
- [CLAUDE.md](CLAUDE.md): the conventions for writing code here (tenancy, units, the engine, forms, gotchas), for people and for Claude Code alike.
- [docs/architecture.md](docs/architecture.md): how each area of the app works and where its code is.
- [docs/engine.md](docs/engine.md): the water balance and projection.
- [docs/decisions.md](docs/decisions.md) and [docs/legacy-audit.md](docs/legacy-audit.md): why it's built this way, and legacy's bugs and the fixes.
- [PLAN.md](PLAN.md): where work stands, what's next and the backlog; [docs/plans/](docs/plans/) the build's record.
- [docs/deployment.md](docs/deployment.md): staging and production, first-time setup and routine deploys.
- [docs/accessibility.md](docs/accessibility.md), [docs/canopy/](docs/canopy/), [docs/weather-corrections/](docs/weather-corrections/), [docs/weather-comparison.md](docs/weather-comparison.md): the accessibility audit, and the research behind the canopy curves and weather corrections.

## 1. Prerequisites

Written for Ubuntu 24.04, natively or under WSL2 on Windows. macOS works too with the Homebrew equivalents.

| Tool | Version | Why |
|---|---|---|
| Ruby | the version in `.ruby-version`, through rbenv | The app |
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

`rustc` is optional in development. With it, ruby-build includes YJIT, Ruby's JIT, which Rails turns on in production. The production image's Ruby already has it; install `rustc` on the staging host so staging gets it too. In development it only makes the app a bit faster.

### Ruby

```bash
# first-time rbenv setup
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
echo 'eval "$(~/.rbenv/bin/rbenv init - bash)"' >> ~/.bashrc && exec bash

# install ruby (from the repo, where rbenv reads the version from .ruby-version)
rbenv install

# if rbenv can't install it, update ruby-build and try again
git -C "$(rbenv root)"/plugins/ruby-build pull

# install gems
bundle install
```

Check YJIT with `ruby --yjit -e 'p RubyVM::YJIT.enabled?'`, which prints `true` if Ruby was built with it. To add YJIT to a Ruby built without it, install `rustc`, then run `rbenv install --force` followed by `bundle install` (the reinstall removes its gems).

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

- **A demo account:** `bin/rails demo:seed` builds the demo operation from `db/demo/farms.yml` (farms on real fields, every kind of irrigation system, plantings and a season of entries) and prints the sign-in. It takes `EMAIL=`, `PASSWORD=` and `YEAR=`, and rerunning it rebuilds the account (keeping the password). After editing the demo in the app, `bin/rails demo:export` writes it back to `db/demo/farms.yml`; the browser tests find the demo by the names in `e2e/demo.json`, so a rename goes there too.
- **The example farm:** `bin/rails demo:example` builds the public, read-only example (`/example`, shown as of July 20 of `YEAR`) from the same file.
- **Weather:** in development, jobs run inside the web server (Active Job's async adapter). Creating a system queues its weather backfill from Open-Meteo, which needs network access. `bin/rails weather:refresh` fetches weather for every active cell now.
- **Email:** mail opens in the browser at http://localhost:3000/letter_opener, so you can sign up and use sign-in links without a mail server.
- **An admin:** `bin/rails runner 'User.find_by!(email: "you@example.com").update!(admin: true)'` opens the admin pages (users, weather status, health check).

## 3. Day to day

```bash
bin/dev                                   # Rails on :3000 and the Vite dev server
bin/ci                                    # everything CI runs (below)
bundle exec rspec spec/path_spec.rb       # one Rails spec file
pnpm test                                 # Vitest (frontend logic and components)
pnpm check                                # svelte-check and TypeScript
bin/e2e                                   # Playwright, on its own database (wisp3_e2e), about 3 minutes; args go to playwright test
bin/e2e e2e/keyboard.spec.ts --project desktop
bin/e2e e2e/smoke.spec.ts -g 'daily entry'
bundle exec standardrb --fix              # Ruby style
bin/rails typelizer:generate              # after changing serializers or routes; commit the output
```

`bin/ci` runs, in order: Ruby style (Standard), frontend style and lint (Prettier, ESLint), type checks, whether the generated TypeScript types and route helpers are current, Vitest, then RSpec (a few minutes). The browser tests are separate: `bin/e2e` builds the Vite assets when they've changed, seeds its own database and runs Playwright on two workers, desktop and phone (dark mode, tests tagged `@phone`). They include an accessibility scan of every page (axe, light and dark, with the reflow checks at 320 px wide and 200% text), keyboard tests and smoke tests. Outside map and soil services are stubbed (`e2e/test.ts`; `E2E_LIVE=1` reaches the real ones), and the seed and the server run on a fixed day (`e2e/clock.json`, as `E2E_NOW`), so the tests pass whatever the date. GitHub Actions runs both, as separate jobs, on every push to `main` and on pull requests (`.github/workflows/ci.yml`). Run all of `bin/e2e` before merging to `main`.

The specs never use the network: Open-Meteo responses are recorded in `spec/fixtures/files/open_meteo`, and WebMock blocks the rest.

### Other tasks

```bash
bin/rails weather:refresh      # fetch weather for every active cell now
bin/rails weather:compare      # AgWeather vs Open-Meteo report → docs/weather-comparison.md
bin/rails weather:recorrect    # count stored days whose weather corrections aren't current; CONFIRM=yes refetches them
bin/rails demo:seed            # rebuild the demo account
bin/rails demo:export          # the demo account, as edited in the app, back to db/demo/farms.yml
bin/rails demo:example         # rebuild the public example farm
```

## 4. Secrets and credentials

| Environment | Where secrets live |
|---|---|
| development, test | `.env` (gitignored), read by dotenv; only `OPEN_METEO_API_KEY`, which is optional |
| staging | `config/credentials/staging.yml.enc` (`database.password`, `open_meteo.api_key`, `secret_key_base`), decrypted by `config/credentials/staging.key` |
| production | The server's `/opt/wisp/.env`, edited by hand (docs/deployment.md, Production step 4): the database password, the Open-Meteo key, the SES SMTP credentials and `RAILS_MASTER_KEY`, with a copy in the password manager. The master key is `config/credentials/production.key`, which decrypts `config/credentials/production.yml.enc`, holding only `secret_key_base` |

Keys are never committed. Keep both `.key` files in the team's password manager. Staging's is copied to the server (docs/deployment.md, Staging step 3); production's is `RAILS_MASTER_KEY` in that `.env`.

Settings read from the environment (`WISP3_DATABASE_PASSWORD`, `OPEN_METEO_API_KEY`) take precedence over credentials, so production needs nothing else in its credentials file.

## 5. Deployment

| Stage | How | Command |
|---|---|---|
| staging (`dev.wisp.cals.wisc.edu`) | Capistrano: Puma and the Solid Queue worker as systemd user services owned by `deploy` | `cap staging deploy` |
| production (AWS: EC2 and RDS; `wisp.cals.wisc.edu`) | Docker Compose: the commit's image built on the server from GitHub, run as `web` (Thruster and Puma) and `jobs` | `bin/production deploy` |

```bash
cap staging deploy                 # main (BRANCH=… for another): packages, assets, migrations, restart
cap staging systemd:status

git push                           # production builds the pushed commit, not your working copy
bin/production deploy [COMMIT]     # build and deploy HEAD; an earlier commit rolls back
bin/production status | images | reload | logs | console | rails … | ssh
```

- **Routine deploys, first-time setup of either server, verifying a deploy, and changing the deploy configuration:** [docs/deployment.md](docs/deployment.md).
- **Building the production image locally:** `docker build --platform linux/amd64 -t wisp3:test .`. To run it, it needs a Postgres, `RAILS_MASTER_KEY`, `WISP3_DATABASE_PASSWORD`, `DB_HOST` and `APP_HOST`.
- **After a deploy,** `https://<host>/up` returns JSON with `status` (`ok`, `degraded` or `down`), the deployed `version` and the morning health check's result. An uptime monitor can watch it.

## 6. Troubleshooting

- **`PG::ConnectionBad` in WSL:** Postgres isn't running. Start it with `sudo service postgresql start`.
- **Vite assets missing or stale in tests:** `bin/e2e` builds them; for RSpec request specs nothing is needed. In development `bin/dev` serves them.
- **Playwright can't launch Chromium:** rerun `pnpm exec playwright install --with-deps chromium`. The `--with-deps` part needs sudo for the system libraries.
- **Stopping a dev server:** stop it by port or PID (`lsof -i :3000`). `pkill -f` with a pattern that also matches your own command line kills the shell running it.
- **`systemctl --user` over SSH says "Failed to connect to bus":** set `XDG_RUNTIME_DIR=/run/user/$(id -u)` first. Capistrano's tasks do this.
- **`bin/production` times out connecting to the server:** SSH is open only to known IP addresses; send IT your current public IP.
- **`bin/production deploy` says the commit "isn't on GitHub":** push it first. Other deploy failures are in docs/deployment.md, Production, Troubleshooting.
- **Browser tests fail on a map or soil layer:** a test is reaching an outside service; import `test` from `e2e/test.ts`, which stubs them.
- **CI says generated types or routes are out of date:** run `bin/rails typelizer:generate` and commit the changes.
