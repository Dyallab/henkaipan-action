# Dockerfile — HenKaiPan GitHub Action
# Minimal image with curl + jq for API communication

FROM alpine:3.19

LABEL "com.github.actions.name"="HenKaiPan Security Scan"
LABEL "com.github.actions.description"="Run security scans in your CI/CD pipeline"
LABEL "com.github.actions.icon"="shield-check"
LABEL "com.github.actions.color"="cyan"

# Install curl and jq for API communication
RUN apk add --no-cache curl jq bash

# Create action user
RUN adduser -D -u 1000 action

COPY entrypoint.sh cleanup.sh /entrypoint.sh /cleanup.sh
RUN chmod +x /entrypoint.sh /cleanup.sh

USER action
ENTRYPOINT ["/entrypoint.sh"]
