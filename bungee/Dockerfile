# ============================================================
# BungeeCord proxy container
#
# Sits in front of all Spigot servers. Handles Mojang auth
# centrally (online_mode: true) and forwards real UUIDs to
# backend servers via ip_forward.
#
# Only this container exposes a Minecraft port to the host.
# ============================================================
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y \
    openjdk-21-jre-headless curl \
    && rm -rf /var/lib/apt/lists/*

# Download BungeeCord JAR
RUN mkdir -p /bungee && \
    curl -fsSL -o /bungee/BungeeCord.jar \
        https://ci.md-5.net/job/BungeeCord/lastSuccessfulBuild/artifact/bootstrap/target/BungeeCord.jar

WORKDIR /bungee

COPY config.yml /bungee-base/config.yml
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Accept EULA-equivalent: BungeeCord has no EULA file,
# but we place an empty accepted marker for clarity
RUN touch /bungee/eula-accepted

EXPOSE 25565

ENTRYPOINT ["/entrypoint.sh"]
