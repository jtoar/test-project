# base
# ------------------------------------------------
FROM node:18-bookworm-slim as base

RUN corepack enable

# We tried to make the Dockerfile as lean as possible. In some cases, that means we excluded a dependency your project needs.
# By far the most common is Python. If you're running into build errors because 'python3' isn't available,
# uncomment the line below here and in other stages as necessary:
RUN apt-get update && apt-get install -y \
    openssl \
    # python3 make gcc \
    && rm -rf /var/lib/apt/lists/*

USER node
WORKDIR /home/node/app

COPY --chown=node:node .yarnrc.yml .
COPY --chown=node:node package.json .
COPY --chown=node:node api/package.json api/
COPY --chown=node:node web/package.json web/
COPY --chown=node:node yarn.lock .

RUN mkdir -p /home/node/.yarn/berry/index

RUN --mount=type=cache,target=/home/node/.yarn/berry/cache,uid=1000 \
    --mount=type=cache,target=/home/node/.cache,uid=1000 \
    CI=1 yarn install

COPY --chown=node:node redwood.toml .
COPY --chown=node:node graphql.config.js .
COPY --chown=node:node .env.defaults .env.defaults

# api build
# ------------------------------------------------
FROM base as api_build

# If your api side build relies on build-time environment variables,
# specify them here as ARGs. (But don't put secrets in your Dockerfile!)
#
# ARG MY_BUILD_TIME_ENV_VAR

COPY --chown=node:node api api
RUN yarn redwood build api

# web build
# ------------------------------------------------
FROM base as web_build

COPY --chown=node:node web web
RUN yarn redwood build web --no-prerender

# production
# ------------------------------------------------
FROM node:18-bookworm-slim as production

RUN corepack enable

RUN apt-get update && apt-get install -y \
    openssl \
    # python3 make gcc \
    && rm -rf /var/lib/apt/lists/*

USER node
WORKDIR /home/node/app

COPY --chown=node:node .yarnrc.yml .
COPY --chown=node:node package.json .
COPY --chown=node:node api/package.json api/
COPY --chown=node:node yarn.lock .

RUN mkdir -p /home/node/.yarn/berry/index

RUN --mount=type=cache,target=/home/node/.yarn/berry/cache,uid=1000 \
    --mount=type=cache,target=/home/node/.cache,uid=1000 \
    CI=1 yarn workspaces focus api --production

COPY --chown=node:node redwood.toml .
COPY --chown=node:node graphql.config.js .
COPY --chown=node:node .env.defaults .env.defaults

COPY --chown=node:node --from=api_build /home/node/app/api/dist /home/node/app/api/dist
COPY --chown=node:node --from=api_build /home/node/app/api/db /home/node/app/api/db
COPY --chown=node:node --from=api_build /home/node/app/node_modules/.prisma /home/node/app/node_modules/.prisma

COPY --chown=node:node --from=web_build /home/node/app/web/dist /home/node/app/web/dist

ENV NODE_ENV=production

CMD [ "node_modules/.bin/rw-server", "--load-env-files" ]

# development
# ------------------------------------------------
FROM base as development

COPY --chown=node:node api api
COPY --chown=node:node web web
COPY --chown=node:node scripts scripts

RUN yarn rw prisma generate
