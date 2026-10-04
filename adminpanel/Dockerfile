# Admin page for the hosting server (see app/main.py).
FROM python:3.12-slim

RUN useradd --system --create-home --uid 2100 app
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY entrypoint.sh /entrypoint.sh
COPY adminctl /usr/local/bin/adminctl
RUN chmod +x /entrypoint.sh /usr/local/bin/adminctl

ENV DATA_DIR=/data KEYS_DIR=/run/keys SERVERS_FILE=/app/servers.json PYTHONUNBUFFERED=1
VOLUME /data
EXPOSE 8000
ENTRYPOINT ["/entrypoint.sh"]
