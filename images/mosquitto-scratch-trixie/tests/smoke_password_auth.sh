#!/usr/bin/env bash
# Smoke: password_file auth works — wrong password rejected, right one
# accepted. Covers the homelab use case (allow_anonymous false + mounted
# password_file).

set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-mosquitto-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-2}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

SERVER="fg028-auth-$$"
TMP=$(mktemp -d)
chmod 0755 "${TMP}"
trap 'docker rm -f "${SERVER}" >/dev/null 2>&1 || true; rm -rf "${TMP}"' EXIT

# Generate a password file via mosquitto_passwd (sidecar).
docker run --rm --entrypoint=/usr/bin/mosquitto_passwd "${IMAGE}" \
  -b -c /tmp/passwd fg028user fg028pass >/dev/null 2>&1 || true
# mosquitto_passwd writes to /tmp/passwd inside the container — docker cp it out.
cid=$(docker create --entrypoint=/usr/bin/mosquitto_passwd "${IMAGE}" -b -c /tmp/passwd fg028user fg028pass)
docker start -a "${cid}" >/dev/null 2>&1
docker cp "${cid}:/tmp/passwd" "${TMP}/passwd"
docker rm "${cid}" >/dev/null
# World-readable so the in-container uid-1883 mosquitto user can read it.
# Production consumers chown this file to 1883; in-test we use 0644 for simplicity.
chmod 0644 "${TMP}/passwd"

# Build a password-required config.
cat > "${TMP}/mosquitto.conf" <<'EOF'
listener 1883
allow_anonymous false
password_file /mosquitto/config/passwd
log_dest stdout
log_type error
log_type warning
log_type notice
log_type information
EOF
chmod 0644 "${TMP}/mosquitto.conf"

# Boot broker with mounted config + passwd.
echo "→ ${IMAGE}: boot broker (allow_anonymous false, password_file set)"
docker run -d --rm --name "${SERVER}" \
  -v "${TMP}/mosquitto.conf:/mosquitto/config/mosquitto.conf:ro" \
  -v "${TMP}/passwd:/mosquitto/config/passwd:ro" \
  "${IMAGE}" >/dev/null
sleep 2

# WRONG credentials should be rejected. mosquitto_pub exits 5 on auth
# failure, so `set -o pipefail` would mask the grep match — capture
# output into a variable first.
set +e
wrong_out=$(docker run --rm --network="container:${SERVER}" \
              --entrypoint=/usr/bin/mosquitto_pub "${IMAGE}" \
              -h localhost -u fg028user -P WRONG -t 'fg028/auth' -m 'nope' 2>&1)
set -e
if grep -qE 'Connection Refused|not authori[zs]ed|not authorized' <<<"${wrong_out}"; then
  echo "  ✓ wrong password rejected"
else
  echo "  ✗ expected 'Connection Refused' / 'not authorized' on wrong password; got:" >&2
  echo "${wrong_out}" >&2
  docker logs "${SERVER}" 2>&1 | tail -10 >&2
  exit 1
fi

# RIGHT credentials should succeed (exit 0).
set +e
docker run --rm --network="container:${SERVER}" \
  --entrypoint=/usr/bin/mosquitto_pub "${IMAGE}" \
  -h localhost -u fg028user -P fg028pass -t 'fg028/auth' -m 'yes' >/dev/null 2>&1
right_rc=$?
set -e
if [[ "${right_rc}" -eq 0 ]]; then
  echo "  ✓ correct password accepted"
else
  echo "  ✗ correct password unexpectedly rejected (rc=${right_rc})" >&2
  docker logs "${SERVER}" 2>&1 | tail -10 >&2
  exit 1
fi
