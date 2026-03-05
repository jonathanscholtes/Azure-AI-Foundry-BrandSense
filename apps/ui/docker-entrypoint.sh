#!/bin/sh
set -e

# Substitute environment variables in nginx config template
# Required env vars:
#   API_URL — the full base URL of the brandsense-api service
#             e.g. https://brandsense-api.gentlehill-abc123.eastus.azurecontainerapps.io
#             Defaults to empty string (relative, same host) for local dev.

: "${API_URL:=http://localhost:8000}"

# Derive base URL (scheme + host, no path) and path prefix from API_URL.
# nginx forbids proxy_pass with a URI path inside a regex location block;
# using the base URL + rewrite works around that restriction.
API_BASE_URL=$(echo "$API_URL" | awk -F/ '{print $1"//"$3}')
API_PATH_PREFIX=$(echo "$API_URL" | sed 's|^[a-zA-Z]*://[^/]*||' | sed 's|/$||')

export API_BASE_URL API_PATH_PREFIX

echo "[entrypoint] Using API_URL=${API_URL}"
echo "[entrypoint] API_BASE_URL=${API_BASE_URL}  API_PATH_PREFIX=${API_PATH_PREFIX}"

envsubst '${API_URL} ${API_BASE_URL} ${API_PATH_PREFIX}' \
  < /etc/nginx/templates/nginx.conf.template \
  > /etc/nginx/conf.d/default.conf

echo "[entrypoint] nginx config written — starting nginx"
exec nginx -g "daemon off;"
