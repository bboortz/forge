#!/usr/bin/env bash
# Regression guard for FG-043 homelab bug 2026-11-10:
#
# prometheus-ipmi-exporter's `ipmi` collector by default invokes
# `/usr/sbin/ipmimonitoring` — which is a 406-byte shell script in
# Debian's freeipmi-tools package. Scratch has no /bin/sh, so if
# ipmi-exporter.yml doesn't configure collector_cmd[ipmi]: ipmi-sensors,
# the collector silently fails and the exporter returns ipmi_up=0 with
# an "exec: 'ipmimonitoring': executable file not found" error in logs —
# WITHOUT failing /metrics (just a label-only health drop).
#
# This smoke boots the image, triggers a /metrics scrape, and inspects
# container logs for the ipmimonitoring-not-found error. If the error
# appears, the config override is broken and we'd ship a silently
# broken image that looks fine to CI.
#
# This is the only smoke that would have caught the 2026-11-10 bug.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-ipmi-exporter-scratch-trixie}"
IMAGE_TAG="${IMAGE_TAG:-1.10}"
REGISTRY="${REGISTRY:-forge-local}"
IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

CID="fg043-elf-$$"
trap 'docker rm -f "${CID}" >/dev/null 2>&1 || true' EXIT

# No /dev/ipmi0 mount — the exporter will try to scrape anyway and emit
# the "exec not found" error if the config override is missing. We're
# checking the SHAPE of the error path, not real BMC success.
docker run -d --rm --name "${CID}" "${IMAGE}" >/dev/null
sleep 3

# Trigger /metrics twice — forces the exporter to sweep every collector
# in its configured list. Without /dev/ipmi0 each collector errors, which
# is fine — we're only looking for the SPECIFIC "ipmimonitoring not found"
# pattern that fires when the config override is missing. 8s of settle
# after the triggers lets docker log flush catch up.
docker exec "${CID}" /hc -t 3 http://127.0.0.1:9290/metrics >/dev/null 2>&1 || true
sleep 2
docker exec "${CID}" /hc -t 3 http://127.0.0.1:9290/metrics >/dev/null 2>&1 || true
sleep 6

logs="$(docker logs "${CID}" 2>&1)"

if echo "${logs}" | grep -qE 'ipmimonitoring.*executable file not found'; then
  echo "  ✗ exporter is calling 'ipmimonitoring' (shell wrapper) — config override missing" >&2
  echo "    This image would ship ipmi_up{collector=\"ipmi\"}=0 on real hardware." >&2
  echo "    Fix: ipmi-exporter.yml must set collector_cmd.ipmi: ipmi-sensors + " >&2
  echo "    custom_args.ipmi: [--output-sensor-state, --ignore-not-available-sensors]" >&2
  echo "--- relevant log lines ---" >&2
  echo "${logs}" | grep "ipmimonitoring" | head -3 >&2
  exit 1
fi

echo "  ✓ exporter config overrides ipmi collector to use ipmi-sensors (no shell wrapper)"
