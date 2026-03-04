#!/bin/sh
set -e

# Substitute environment variables in nginx config template
# Required env vars:
#   API_URL — the full base URL of the brandsense-api service
#             e.g. https://brandsense-api.gentlehill-abc123.eastus.azurecontainerapps.io
#             Defaults to empty string (relative, same host) for local dev.

: "${API_URL:=http://localhost:8000}"

echo "[entrypoint] Using API_URL=${API_URL}"

envsubst '${API_URL}' \
  < /etc/nginx/templates/nginx.conf.template \
  > /etc/nginx/conf.d/default.conf

echo "[entrypoint] nginx config written — starting nginx"
exec nginx -g "daemon off;"
