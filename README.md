# HenKaiPan Security Scan GitHub Action
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](./LICENSE)

Run security scans (SAST, SCA, secrets, vulnerability scanning) in your GitHub Actions CI/CD pipeline. Scans are powered by [HenKaiPan](https://github.com/Dyallab/henkaipan) — a self-hosted security posture manager.

---

## ⚡ Quick Start (< 2 minutes)

### 1. Create an API Token

1. Go to your HenKaiPan instance → **Settings → API Tokens**
2. Click **New Token**, give it a name (e.g. `GitHub Actions`)
3. Copy the token — it's shown **only once**

### 2. Add it as a GitHub Secret

1. In your GitHub repository, go to **Settings → Secrets and variables → Actions**
2. Click **New repository secret**
3. Name: `HENKAIPAN_API_KEY`, Value: paste your token

### 3. Add the workflow file

Create `.github/workflows/security.yml`:

```yaml
name: HenKaiPan Security Scan

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  security-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run HenKaiPan Security Scan
        uses: dyallab/henkaipan-action@v1
        with:
          api-url: https://app.henkaipan.com       # or your self-hosted URL
          api-key: ${{ secrets.HENKAIPAN_API_KEY }}
          project-id: your-project-uuid
          scanners: all
          fail-on-severity: critical
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

That's it. The action will trigger a scan and poll until completion.

### Enable PR Comments

To get scan results posted as comments on your Pull Requests, you need two things:

1. Pass `GITHUB_TOKEN` as an environment variable (as shown above)
2. Grant `pull-requests: write` permission to the workflow:

```yaml
jobs:
  security-scan:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write       # required for PR comments
    steps:
      - uses: actions/checkout@v4

      - name: Run HenKaiPan Security Scan
        uses: dyallab/henkaipan-action@v1
        with:
          api-url: https://app.henkaipan.com
          api-key: ${{ secrets.HENKAIPAN_API_KEY }}
          project-id: your-project-uuid
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

PR comments are posted automatically on `pull_request` events. The action also writes results to the **GitHub Actions Summary tab** for all event types (push, manual, etc).

---

## 📡 Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `api-url` | Yes | — | Base URL of your HenKaiPan instance |
| `api-key` | Yes | — | API token (stored as a GitHub Secret) |
| `project-id` | Yes | — | UUID of the project to scan |
| `scanners` | No | `all` | Comma-separated list or pack (`all`, `sast`, `sca`, `secrets`, `vuln`, `containers`) |
| `fail-on-severity` | No | _(none)_ | Exit code 1 if findings ≥ severity (`critical`, `high`, `medium`, `low`) |
| `scan-branch` | No | current branch | Git branch to scan |
| `post-pr-comment` | No | `true` | Post a summary comment to the GitHub Pull Request with scan results |
| `cf-access-client-id` | No | — | Cloudflare Access Service Token Client ID (for instances behind a Cloudflare Tunnel) |
| `cf-access-client-secret` | No | — | Cloudflare Access Service Token Client Secret (for instances behind a Cloudflare Tunnel) |

### Available Scanner Packs

| Pack | Scanners |
|------|----------|
| `all` | semgrep, trivy, gitleaks, grype, nuclei |
| `sast` | semgrep |
| `sca` | trivy, grype |
| `secrets` | gitleaks |
| `vuln` | grype, nuclei |
| `containers` | trivy, grype |

To specify individual scanners: `scanners: semgrep,trivy,gitleaks`

---

## 📤 Outputs

| Output | Description |
|--------|-------------|
| `scan-id` | Comma-separated scan IDs |
| `finding-count` | Total findings |
| `finding-critical` | Critical findings count |
| `finding-high` | High findings count |
| `finding-medium` | Medium findings count |
| `finding-low` | Low findings count |

---

## 🔧 Examples

### Fail the pipeline on high or critical findings

```yaml
- name: Run HenKaiPan Security Scan
  uses: dyallab/henkaipan-action@v1
  with:
    api-url: https://app.henkaipan.com
    api-key: ${{ secrets.HENKAIPAN_API_KEY }}
    project-id: ${{ secrets.HENKAIPAN_PROJECT_ID }}
    scanners: all
    fail-on-severity: high
```

### Scan only SAST (semgrep) on PRs

```yaml
- name: Run SAST Scan
  uses: dyallab/henkaipan-action@v1
  with:
    api-url: https://app.henkaipan.com
    api-key: ${{ secrets.HENKAIPAN_API_KEY }}
    project-id: ${{ secrets.HENKAIPAN_PROJECT_ID }}
    scanners: sast
    fail-on-severity: medium
```

### Self-hosted instance (private network)

For HenKaiPan behind a VPN or internal network, use a **self-hosted runner** on the same network:

```yaml
jobs:
  security-scan:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4

      - name: Run HenKaiPan Security Scan
        uses: dyallab/henkaipan-action@v1
        with:
          api-url: http://10.0.0.5:8080
          api-key: ${{ secrets.HENKAIPAN_API_KEY }}
          project-id: your-project-uuid
          scanners: all
```

### Self-hosted behind Cloudflare Tunnel

For HenKaiPan behind a Cloudflare Tunnel with Access policies, authenticate via a **Service Token**:

1. In Cloudflare Zero Trust → **Access → Service Auth** → create a Service Token
2. Copy the **Client ID** and **Client Secret**
3. Add them as GitHub secrets (e.g. `CF_CLIENT_ID` and `CF_CLIENT_SECRET`)
4. In Cloudflare Access → your app → add a policy that requires the Service Token

```yaml
- name: Run HenKaiPan Security Scan
  uses: dyallab/henkaipan-action@v1
  with:
    api-url: https://henkaipan.internal.yourdomain.com
    api-key: ${{ secrets.HENKAIPAN_API_KEY }}
    project-id: ${{ secrets.HENKAIPAN_PROJECT_ID }}
    scanners: all
    cf-access-client-id: ${{ secrets.CF_CLIENT_ID }}
    cf-access-client-secret: ${{ secrets.CF_CLIENT_SECRET }}
```

The action automatically adds `CF-Access-Client-Id` and `CF-Access-Client-Secret` headers to every API request when both values are provided.

### Disable PR comments

By default, the action posts a comment to the PR with findings summary. To disable:

```yaml
- name: Run HenKaiPan Security Scan
  uses: dyallab/henkaipan-action@v1
  with:
    api-url: https://app.henkaipan.com
    api-key: ${{ secrets.HENKAIPAN_API_KEY }}
    project-id: ${{ secrets.HENKAIPAN_PROJECT_ID }}
    scanners: all
    post-pr-comment: "false"
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### GitHub Actions Step Summary

In addition to PR comments, the action writes scan results to the **Actions Summary tab** (visible in the GitHub Actions run page). This works for all event types — push, pull_request, workflow_dispatch, etc.

No extra configuration needed — it uses the built-in `$GITHUB_STEP_SUMMARY` environment variable.

---

## 🔒 Security Best Practices

- **Never** hardcode API tokens in workflow files — use GitHub Secrets
- Create tokens with **minimal scope** — project-scoped tokens can only trigger scans for that project
- Tokens are shown **only once** at creation time — store them immediately
- Rotate tokens regularly (Settings → API Tokens → Revoke old → Create new)
- For private networks, ensure the runner has access to the HenKaiPan instance

---

## ❓ FAQ

**Q: The scan keeps timing out.**  
A: Default max wait is 20 minutes. For large repos, consider using `scanners: semgrep,trivy` instead of `all`, or increase the worker pool size on your HenKaiPan instance.

**Q: The action fails with "token is not scoped to this project".**  
A: The token was created with a specific project scope and you're trying to scan a different project. Create a new token without a project scope, or use a token scoped to the correct project.

**Q: Can I use this for GitLab CI / Jenkins / CircleCI?**  
A: Yes! The action is just a Docker container. Any CI system that can run a Docker container can use it. See the [CI/CD Integration docs](https://henkaipan.com/docs/architecture/ci-cd-integration) for examples.

**Q: How do I see the full scan results?**  
A: Log in to your HenKaiPan instance → Scans → select the scan ID. The action outputs `scan-id` so you can reference them in follow-up steps.

**Q: Can I block merges based on findings?**  
A: Yes. Set `fail-on-severity` to the minimum severity that should block. For example, `critical` will exit with code 1 only if critical findings exist.

---

## 📋 Action Versioning

| Version | Description |
|---------|-------------|
| `v1` | Latest stable release |
| `v1.0.0` | Pin to specific version |
| `@main` | Bleeding edge (not recommended) |

Recommend pinning to `v1` or a specific tag (`v1.0.0`) in production.

---

## 🐳 Docker

The action is a Docker container. You can also run it manually:

```bash
docker run \
  -e HENKAIPAN_API_URL=https://app.henkaipan.com \
  -e HENKAIPAN_API_KEY=your-token \
  -e HENKAIPAN_PROJECT_ID=your-project-uuid \
  -e HENKAIPAN_SCANNERS=all \
  dyallab/henkaipan-action:v1
```

Or with arguments:

```bash
docker run \
  dyallab/henkaipan-action:v1 \
  "https://app.henkaipan.com" "hkp_your_token" "project-uuid" "all" "critical" ""
```

---

## 📄 License

MIT — see [LICENSE](./LICENSE)
