# ---------------------------------------------------------------------------
# Stage 1 — build the Vite/React app
# ---------------------------------------------------------------------------
FROM node:20-slim AS builder

WORKDIR /app

# Install dependencies first (layer cache)
COPY package.json ./
RUN npm install

# Copy source and build
COPY . .
RUN npm run build

# ---------------------------------------------------------------------------
# Stage 2 — serve with nginx
# Nginx proxies /validate, /tools, /health → brandsense-api (API_URL env var)
# ---------------------------------------------------------------------------
FROM nginx:1.27-alpine AS runtime

# Remove default nginx site config
RUN rm -f /etc/nginx/conf.d/default.conf

# Copy nginx config template and entrypoint
COPY nginx.conf.template /etc/nginx/templates/nginx.conf.template
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Copy Vite build output
COPY --from=builder /app/dist /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:80/ || exit 1

# envsubst is included in nginx:alpine; entrypoint writes the final config
ENTRYPOINT ["/docker-entrypoint.sh"]
