FROM alpine:3.21

RUN apk add --no-cache bash curl jq tzdata

# supercronic — cron for containers (pinned + checksum verified)
ENV SUPERCRONIC_URL=https://github.com/aptible/supercronic/releases/download/v0.2.34/supercronic-linux-amd64 \
    SUPERCRONIC_SHA1SUM=e8631edc1775000d119b70fd40339a7238eece14
RUN curl -fsSLO "$SUPERCRONIC_URL" \
    && echo "${SUPERCRONIC_SHA1SUM}  supercronic-linux-amd64" | sha1sum -c - \
    && chmod +x supercronic-linux-amd64 \
    && mv supercronic-linux-amd64 /usr/local/bin/supercronic

COPY railway.sh /usr/local/bin/railway.sh
COPY startup.sh /startup.sh
RUN chmod +x /usr/local/bin/railway.sh /startup.sh

RUN mkdir -p /app

CMD ["/startup.sh"]
