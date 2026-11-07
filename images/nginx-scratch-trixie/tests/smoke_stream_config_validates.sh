#!/usr/bin/env bash
# FG-016: validate that homelab/sni-router's nginx.conf.j2 — the canonical
# SNI-routing + HTTP-routing config beaconry/homelab devs maintain — passes
# `nginx -t` inside this scratch image with only three MINIMAL homelab-side
# edits documented below.
#
# Delivers: FG-016 Scenario "sni-router config works by mounting into scratch".
#
# Homelab-side edits required to adopt this image (one-time, 3 lines):
#   1. `user nginx;`                   → `user www-data;`
#      (Forge follows Debian's nginx package convention; `nginx` user doesn't exist.)
#   2. Add `load_module modules/ngx_stream_module.so;` at top of config
#      (Debian compiles stream as a dynamic module; sni-router's pre-FG-016
#      image used alpine's statically-compiled nginx.)
#   3. `pid /var/run/nginx.pid;`       → `pid /tmp/nginx.pid;`
#      (/var/run isn't pre-created writable in scratch; /tmp is 1777 from
#      the baseline — standard scratch convention.)
#
# Zero other edits. Jinja placeholders substituted with test values.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-nginx-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-1.26}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

tmp=$(mktemp -d); trap 'rm -rf "${tmp}"' EXIT

# This is homelab/sni-router/nginx.conf.j2 verbatim, with:
#   - jinja `{{ ... }}` placeholders → test values
#   - jinja `{% for %}` loop → empty expansion
#   - the three FG-016 adoption edits (see header)
cat > "${tmp}/nginx.conf" <<'CONF'
load_module modules/ngx_stream_module.so;

user  www-data;
worker_processes  auto;
error_log  /var/log/nginx/error.log notice;
pid        /tmp/nginx.pid;

events {
    worker_connections  1024;
}

# HTTPS routing — SSL passthrough, no TLS termination here
stream {
    # Docker embedded DNS — resolve per-request so missing containers don't block startup
    resolver 127.0.0.11 valid=10s;

    map $ssl_preread_server_name $ssl_backend {
        example.local       website-proxy-1:443;
        cloud.example.local nextcloud-proxy-1:443;
        # unknown SNI → port 1 (nothing listens → immediate ECONNREFUSED)
        default                 127.0.0.1:1;
    }

    server {
        listen 443;
        proxy_pass $ssl_backend;
        ssl_preread on;
    }
}

# HTTP routing — layer 7, route by Host header
http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    resolver 127.0.0.11 valid=10s;

    map $host $http_backend {
        example.local       website-proxy-1:80;
        cloud.example.local nextcloud-proxy-1:80;
        default             "";
    }

    server {
        listen 80;

        # Health check endpoint (not forwarded upstream)
        location = /health {
            access_log off;
            return 200 "ok\n";
            add_header Content-Type text/plain;
        }

        location / {
            if ($http_backend = "") {
                return 444;
            }
            proxy_pass         http://$http_backend;
            proxy_set_header   Host              $host;
            proxy_set_header   X-Real-IP         $remote_addr;
            proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_set_header   X-Forwarded-Proto $scheme;
        }
    }
}
CONF

set +e
out=$(docker run --rm \
  -v "${tmp}/nginx.conf:/etc/nginx/nginx.conf:ro" \
  --entrypoint=/usr/sbin/nginx \
  "${IMAGE}" -t 2>&1)
rc=$?
set -e

if [[ ${rc} -ne 0 ]]; then
  echo "  ✗ nginx -t rc=${rc}" >&2
  echo "${out}" >&2
  exit 1
fi
if ! grep -q 'syntax is ok' <<<"${out}"; then
  echo "  ✗ nginx -t output missing 'syntax is ok':" >&2; echo "${out}" >&2
  exit 1
fi
if ! grep -q 'test is successful' <<<"${out}"; then
  echo "  ✗ nginx -t output missing 'test is successful':" >&2; echo "${out}" >&2
  exit 1
fi

echo "  ✓ homelab/sni-router nginx.conf.j2 passes nginx -t (3-line adoption diff)"
