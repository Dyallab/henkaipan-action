# Dockerfile — HenKaiPan GitHub Action
# Minimal image with curl + jq for API communication

FROM alpine:3.22

LABEL "com.github.actions.name"="HenKaiPan Security Scan"
LABEL "com.github.actions.description"="Run security scans in your CI/CD pipeline"

RUN apk add --no-cache curl jq bash
RUN adduser -D -u 1000 action

COPY entrypoint.sh cleanup.sh /
RUN chmod +x /entrypoint.sh /cleanup.sh

USER action
ENTRYPOINT ["/entrypoint.sh"]
