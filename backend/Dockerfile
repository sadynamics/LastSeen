# ---- Dependencies ----
FROM node:20-alpine AS deps
WORKDIR /app
RUN apk add --no-cache libc6-compat openssl python3 make g++
COPY package.json package-lock.json* ./
RUN npm ci --include=dev

# ---- Build ----
FROM node:20-alpine AS build
WORKDIR /app
RUN apk add --no-cache libc6-compat openssl
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npx prisma generate \
 && npm run build \
 && npm prune --omit=dev

# ---- Runtime ----
FROM node:20-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=3000
RUN apk add --no-cache tini ca-certificates openssl libc6-compat && \
    addgroup -S app && adduser -S app -G app

COPY --from=build --chown=app:app /app/node_modules ./node_modules
COPY --from=build --chown=app:app /app/dist ./dist
COPY --from=build --chown=app:app /app/prisma ./prisma
COPY --chown=app:app package.json ./
COPY --chown=app:app scripts ./scripts

USER app
EXPOSE 3000
ENTRYPOINT ["/sbin/tini", "--"]
# Default to API. Worker service overrides via Railway's `Start Command`
# (or by setting RAILWAY_CONFIG_FILE=railway.worker.json).
CMD ["node", "scripts/start-api.js"]
