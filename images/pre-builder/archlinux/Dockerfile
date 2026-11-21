# syntax=docker/dockerfile:1.7
#
# FG-081: forge-rooted Arch Linux pre-builder. Third OS family in the
# fleet (after Debian + Ubuntu + Alpine). pacman-based upgrade + CA on
# top of archlinux:latest.
#
# Consumers (post-FG-081): base/archlinux (public API); future
# gamepad-archlinux + any Arch runtime that needs rolling-current
# packages (python-evdev, kernel-ABI-matched hardware access tools, etc.).
#
# Shell + pacman kept (image.has-shell contract — this IS a slim-tier
# base). Rolling-release model: daily cron re-resolves archlinux:latest
# + picks up fresh pacman mirror snapshots; scan-baseline.json drifts
# more than any other pre-builder (parallel to debian-slim-sid).
#
# DELTA vs other forge pre-builders: dumb-init is NOT shipped. Neither
# dumb-init nor tini live in Arch's core/extra repos (only AUR, which
# forge doesn't trust without makepkg from base-devel). Consumers that
# need PID-1 signal handling install their own (e.g. via pacman -S from
# AUR in the derived image, or COPY-from a dumb-init builder stage).

# Literal FROM (not ARG-indirected) so FG-042's upstream-grep invariant
# can cheaply catch future drift. archlinux:latest is the ONLY tag Arch
# publishes meaningfully (date-stamped tags defeat cron-rolling per
# FG-081 story §6). DL3007 is documented accordingly in the plan doc.
# hadolint ignore=DL3007
FROM archlinux:latest

ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.source="https://github.com/bboortz/forge"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.description="Forge-rooted Arch Linux pre-builder — pacman -Syu + CA certs, published for every Arch consumer to FROM instead of archlinux:latest directly (FG-081). NOTE no dumb-init (not in Arch core/extra)."
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"

# pacman upgrade + install ca-certificates. `-Syu --noconfirm` does the
# full rolling-sync; `-Scc` nukes the pacman package cache so it doesn't
# bloat the final image (parallel to Debian pre-builders' apt lists
# cleanup).
RUN set -eux; \
    pacman -Syu --noconfirm ca-certificates; \
    update-ca-trust; \
    pacman -Scc --noconfirm; \
    rm -rf /var/cache/pacman/pkg/* /var/lib/pacman/sync/*
