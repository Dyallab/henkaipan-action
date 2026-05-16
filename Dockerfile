# Dockerfile — HenKaiPan GitHub Action
# Minimal image with curl + jq for API communication

FROM alpine:3.22

LABEL "com.github.actions.name"="HenKaiPan Security Scan"
LABEL "com.github.actions.description"="Run security scans in your CI/CD pipeline"

RUN apk add --no-cache curl jq bash
COPY entrypoint.sh cleanup.sh /
RUN chmod +x /entrypoint.sh /cleanup.sh

ENTRYPOINT ["/entrypoint.sh"]
