# ============================================================
# Spigot container — multi-stage build
#
# Stage 1: Build the script4kids plugin from source
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

# ── Stage 1: Build plugin ───────────────────────────────────
FROM debian:trixie-slim AS plugin-builder

RUN apt-get update && apt-get install -y openjdk-21-jdk git maven && rm -rf /var/lib/apt/lists/*

RUN git clone --depth=1 https://github.com/cndrbrbr/script4kids.git /build
WORKDIR /build
RUN mvn clean package -DskipTests -q

# ── Stage 2: Runtime ────────────────────────────────────────
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y \
    openjdk-21-jdk git curl inotify-tools \
    openssh-server sudo zip unzip jq python3-minimal \
    && rm -rf /var/lib/apt/lists/*

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

# Plugin JAR
COPY --from=plugin-builder /build/target/jsmn-1.0-SNAPSHOT.jar plugins/

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
