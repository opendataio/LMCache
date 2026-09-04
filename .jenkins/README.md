# LMCache Jenkins CI POC

## Background

[Issue #4861](https://github.com/LMCache/LMCache/issues/4861) proposes a CI architecture
that supports hardware-vendor-managed test infrastructure (e.g. RBLN accelerators).
The core challenge: vendor machines live on internal networks, so GitHub Actions cannot
reach them directly, and a human approval gate is required before tests actually run.

This directory provides a POC implementation of that design.

## Architecture

```
           GitHub (LMCache)
           PR + '<x>' label
                   │
      ┌────────────┴────────────┐
      │                         │
Internal Jenkins          External Jenkins
Jenkinsfile.poller        Jenkinsfile.webhook
(polls every 5 min)       (Generic Webhook Trigger)
      │                         │
      └────────────┬────────────┘
                   │ trigger
                   ▼
          lmcache-rbln-test
          (Jenkinsfile.test)
       ┌──────────────────────┐
       │ approval → test      │
       │ → report results     │
       └──────────┬───────────┘
                  │
           GitHub PR status
           + comment
```

`Jenkinsfile.test` is shared between both modes — only the trigger mechanism differs.

## Two deployment modes

### Internal Jenkins (polling)

Use when Jenkins is on an internal network that GitHub cannot reach.

| File | Role |
|------|------|
| `Jenkinsfile.poller` | Polls GitHub API every 5 min for PRs labelled `rbln`, triggers test job on new SHAs |
| `Jenkinsfile.test` | Runs on triggered SHA: approval gate → checkout → tests → report |

**Setup:**
1. Jenkins credential ID `GITHUB_PAT` — PAT with `repo:status` and `public_repo` scopes
2. Create Pipeline job `lmcache-rbln-poller` → Script Path: `.jenkins/Jenkinsfile.poller`
3. Create Pipeline job `lmcache-rbln-test` → Script Path: `.jenkins/Jenkinsfile.test`
4. Install plugins: Pipeline Utility Steps, Workspace Cleanup, Rebuild

### External Jenkins (webhook)

Use when Jenkins has a public URL and GitHub can push events directly.

| File | Role |
|------|------|
| `Jenkinsfile.webhook` | Receives GitHub `pull_request` webhook, triggers test job immediately |
| `Jenkinsfile.test` | Same as above — shared between both modes |

**Setup:**
1. Same credential and `lmcache-rbln-test` job as above
2. Install additional plugins: Generic Webhook Trigger, Rebuild
3. Create Pipeline job `lmcache-rbln-webhook` → Script Path: `.jenkins/Jenkinsfile.webhook`
4. Add GitHub webhook on the repo:
   - Payload URL: `https://<jenkins-host>/generic-webhook-trigger/invoke?token=rbln-webhook-secret`
   - Content type: `application/json`
   - Events: Pull requests

## Spinning up Jenkins

A Docker-based Jenkins instance is provided under `docker/`. Plugins are pre-installed
at image build time via `docker/plugins.txt` — no manual plugin installation needed.

**Requirements:** Docker, Docker Compose

```bash
cd .jenkins/docker
docker-compose build      # builds image and installs all plugins from plugins.txt
docker-compose up -d      # starts Jenkins at http://localhost:8080
```

Default credentials: `admin` / `admin`

**Configure the GitHub PAT** (one-time, persisted in the Jenkins volume):

1. Go to **Manage Jenkins → Credentials → System → Global → Add Credentials**
2. Kind: `Secret text`
3. ID: `GITHUB_PAT`
4. Secret: a GitHub PAT with `repo:status` and `public_repo` scopes
5. Save

**Plugins installed by `docker/plugins.txt`:**

| Plugin | Purpose |
|--------|---------|
| `workflow-aggregator` | Core Pipeline support |
| `pipeline-graph-view` | Pipeline stage graph overview |
| `pipeline-utility-steps` | `readJSON`, `fileExists` |
| `ws-cleanup` | `cleanWs()` |
| `rebuild` | Re-run a build with same parameters |
| `credentials` + `credentials-binding` | Secure secret injection |
| `configuration-as-code` | Jenkins config as code (casc.yaml) |
| `generic-webhook-trigger` | Webhook-based triggering (external mode) |
| `github` | GitHub integration |
| `git` | Source checkout |

To add a plugin: append it to `docker/plugins.txt` and rebuild the image.

## Current features

- Label-based PR targeting (`rbln` label triggers the pipeline)
- Human approval gate before tests run (24-hour timeout)
- Commit status reported at each stage (`pending` → `success` / `failure`)
- PR comment posted with test outcome, failed test names, and error summary
- Deduplication via seen-SHA file (polling mode only)

## Validated

End-to-end pipeline verified on [opendataio/LMCache#1](https://github.com/opendataio/LMCache/pull/1):
poller detected the labelled PR, triggered the test job, approval flowed through,
and results were posted back as both a commit status and a PR comment.

## Future extensions

- Handle `synchronize` events (new commits to already-labelled PRs) in webhook mode
- Multi-vendor matrix: replicate the pattern for other hardware labels (e.g. `amd`, `xpu`)
- Attach full test logs as a GitHub Gist and link from the PR comment
- Replace the seen-SHA flat file with a more robust state store
