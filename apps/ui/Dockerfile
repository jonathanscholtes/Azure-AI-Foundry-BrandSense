# ---------------------------------------------------------------------------
# Stage 1 — build the Vite/React app
# ---------------------------------------------------------------------------
FROM node:20-alpine AS builder

WORKDIR /app

# Install dependencies first (layer cache)
COPY package.json ./
RUN npm install

# Copy source and build
COPY . .
RUN npm run build

# ---------------------------------------------------------------------------
# Stage 2 — serve with nginx
# Static nginx.conf proxies /validate, /tools, /health → http://brnd-api
# (same Container Apps environment, internal HTTP, no TLS required).
# ---------------------------------------------------------------------------
FROM nginx:1.25-alpine AS runtime

# Copy static nginx config and Vite build output
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html

# Drop root
RUN sed -i '/^user /d' /etc/nginx/nginx.conf \
    && addgroup -S app && adduser -S app -G app \
    && chown -R app:app \
         /usr/share/nginx/html \
         /var/cache/nginx \
         /var/log/nginx \
         /etc/nginx/conf.d \
    && touch /var/run/nginx.pid && chown app:app /var/run/nginx.pid

USER app

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:80/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
