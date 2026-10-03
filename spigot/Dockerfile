# ============================================================
# Spigot container — multi-stage build
#
# Stage 1: GraalVM JDK
# Stage 2: Runtime image with SSH access for students
#
# Each container exposes:
#   25565  — Minecraft server (mapped to different host ports)
#   22     — SSH (SFTP for FileZilla + restricted shell for PuTTY)
#
# Two SSH users per container:
#   mc-sftp  — FileZilla SFTP access, chrooted to /server
#   mc-ctrl  — PuTTY access, dispatched via /mc-dispatch.sh (start / stop / version / restore)
# ============================================================

# ── Stage 1: GraalVM JDK ────────────────────────────────────
# Pull the official GraalVM Community image and copy the JDK out of it.
# JDK 25 is required to build/run newer Minecraft versions (e.g. the 26.x
# line) via BuildTools — bump this again if a future Minecraft version
# requires a newer Java than this image supports.
FROM ghcr.io/graalvm/jdk-community:25 AS graalvm-jdk
RUN cp -r "$JAVA_HOME" /opt/graalvm-jdk

# ── Stage 2: Runtime ────────────────────────────────────────
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y \
    git curl inotify-tools \
    openssh-server sudo zip unzip jq python3-minimal \
    && rm -rf /var/lib/apt/lists/*

# GraalVM Community JDK 25 — copied from official image above
COPY --from=graalvm-jdk /opt/graalvm-jdk /opt/graalvm
ENV JAVA_HOME=/opt/graalvm
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# Pre-download BuildTools so the container doesn't need internet at startup
RUN mkdir -p /buildtools && \
    curl -fsSL -o /buildtools/BuildTools.jar \
        https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar

# ── SSH users ────────────────────────────────────────────────
# mc-sftp: SFTP-only, chrooted to /server (FileZilla)
# mc-ctrl: restricted shell, dispatched via /mc-dispatch.sh (PuTTY)
RUN groupadd -g 2001 mc-sftp && \
    useradd -u 2001 -g mc-sftp -s /usr/sbin/nologin -M mc-sftp && \
    groupadd -g 2002 mc-ctrl && \
    useradd -u 2002 -g mc-ctrl -s /bin/bash -m mc-ctrl

RUN mkdir -p /home/mc-sftp/.ssh /home/mc-ctrl/.ssh && \
    chown mc-sftp:mc-sftp /home/mc-sftp/.ssh && \
    chown mc-ctrl:mc-ctrl /home/mc-ctrl/.ssh && \
    chmod 700 /home/mc-sftp/.ssh /home/mc-ctrl/.ssh

# mc-ctrl may only sudo the control scripts (no TTY required)
RUN printf 'Defaults !requiretty\nmc-ctrl ALL=(root) NOPASSWD: /mc-start.sh, /mc-stop.sh, /mc-version.sh, /mc-restore.sh, /mc-adduser.sh\n' \
    > /etc/sudoers.d/mc-ctrl && chmod 440 /etc/sudoers.d/mc-ctrl

WORKDIR /server-base

# Plugin JARs
# script4kids (jsmn) publishes one release per Minecraft version (tag
# v<version>-mc<minecraft>). Both are kept in the image; entrypoint.sh copies
# the one matching the server's current version before every start, since
# students can switch versions with 'version <x.y.z>'.
ARG JSMN_VERSION=1.1.0
RUN for mc in 1.21.11 26.3; do \
        mkdir -p "plugins-mc/$mc" && \
        curl -fsSL -o "plugins-mc/$mc/jsmn-${JSMN_VERSION}-mc$mc.jar" \
            "https://github.com/cndrbrbr/script4kids/releases/download/v${JSMN_VERSION}-mc$mc/jsmn-${JSMN_VERSION}-mc$mc.jar" \
        || exit 1; \
    done
COPY minecraft-prometheus-exporter.jar plugins/
COPY prometheus-exporter-config.yml plugins/PrometheusExporter/config.yml

# Server config
COPY eula.txt server.properties whitelist.json spigot.yml ./

# Scripts
COPY entrypoint.sh   /entrypoint.sh
COPY watch_copy.sh   /watch_copy.sh
COPY mc-dispatch.sh  /mc-dispatch.sh
COPY mc-start.sh     /mc-start.sh
COPY mc-stop.sh      /mc-stop.sh
COPY mc-version.sh   /mc-version.sh
COPY mc-restore.sh   /mc-restore.sh
COPY mc-adduser.sh   /mc-adduser.sh

# SSH server config
COPY sshd_config /etc/ssh/sshd_config

RUN chmod +x /entrypoint.sh /watch_copy.sh /mc-dispatch.sh /mc-start.sh /mc-stop.sh /mc-version.sh /mc-restore.sh /mc-adduser.sh

WORKDIR /server

EXPOSE 25565 22

ENTRYPOINT ["/entrypoint.sh"]
