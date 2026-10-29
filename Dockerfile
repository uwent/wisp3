# syntax=docker/dockerfile:1
# The production image: Thruster (HTTPS with Let's Encrypt) in front of Puma, or the Solid Queue
# worker with `bin/jobs`. Built on the EC2 server by `bin/production deploy` and run there by
# config/deploy/compose.production.yaml; see docs/deployment.md, Production.

ARG RUBY_VERSION=4.0.5
ARG NODE_VERSION=24

FROM docker.io/library/node:${NODE_VERSION}-slim AS node

FROM docker.io/library/ruby:${RUBY_VERSION}-slim AS base

WORKDIR /rails

# libpq for Postgres, jemalloc for Ruby's memory use, curl for the container health check
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libpq5 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Gems, pnpm packages and the Vite build
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Node only at build time; corepack gives the pnpm pinned in package.json
COPY --from=node /usr/local/bin/node /usr/local/bin/
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT="0" HUSKY="0"
RUN ln -s ../lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack && corepack enable pnpm

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile

COPY . .

RUN bundle exec bootsnap precompile -j 1 app/ lib/ && \
    SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile && \
    rm -rf node_modules tmp/cache

# The runtime image: no compilers or Node
FROM base

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# The deployed commit, shown by /up (HealthController.version)
ARG REVISION
RUN if [ -n "$REVISION" ]; then echo "$REVISION" > REVISION; fi

# Run as a non-root user; storage/thruster holds Let's Encrypt's certificates (a volume)
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p storage/thruster && \
    chown -R rails:rails log storage tmp
USER 1000:1000

EXPOSE 80 443
CMD ["./bin/thrust", "./bin/rails", "server"]
