# GitHub Webhook + Jenkins Integration Guide (MetaX)

## Overview

When Jenkins has a public URL, GitHub can push `pull_request` events directly to it.
A PR labeled **`metax`** triggers the test pipeline automatically.

```
GitHub PR labeled 'metax'
        │  (webhook)
        ▼
lmcache-metax-webhook   ← receives event, extracts SHA
        │  (trigger)
        ▼
lmcache-metax-test      ← approval gate → run tests → post result to PR
```

---

## Prerequisites

- Jenkins reachable from the internet over HTTPS
- Plugins installed: **Generic Webhook Trigger**, **Pipeline Utility Steps**, **Workspace Cleanup**
- A GitHub PAT with `repo:status` and `public_repo` scopes

---

## Step 1 — Store credentials in Jenkins

Add two credentials under **Manage Jenkins → Credentials → Global → Add Credentials**:

| ID | Kind | Secret value |
|----|------|-------------|
| `GITHUB_PAT` | Secret text | GitHub PAT — used by Jenkins to post commit statuses back to the PR |
| `metax-webhook-token` | Secret text | Webhook token — used to authenticate requests from GitHub to Jenkins (see Step 3) |

---

## Step 2 — Create Jenkins jobs

**Job 1: `lmcache-metax-webhook`**
- Type: Pipeline, Script Path: `.jenkins/Jenkinsfile.webhook`
- Receives the webhook event pushed by GitHub and triggers `lmcache-metax-test`.
  The `GenericTrigger` block reads the token from the `metax-webhook-token` credential automatically — no manual trigger configuration needed.

**Job 2: `lmcache-metax-test`**
- Type: Pipeline, Script Path: `.jenkins/Jenkinsfile.test`
- Runs the actual tests. Add MetaX-specific steps in `.jenkins/run_tests.sh`.
- Results are automatically reported back to GitHub:
  - **Commit status** (`jenkins/metax`) — visible in the PR checks list

---

## Step 3 — Add webhook on GitHub

Go to the repo **Settings → Webhooks → Add webhook**:

| Field | Value |
|-------|-------|
| Payload URL | `https://<jenkins-host>/generic-webhook-trigger/invoke?token=<secret-value-of-metax-webhook-token>` |
| Content type | `application/json` |
| Events | **Pull requests** only |

Click **Add webhook**. GitHub sends a `ping` — a green tick confirms Jenkins is reachable.

---

## Step 4 — Test it

1. Open a PR and add the **`metax`** label
2. Jenkins receives the event, triggers `lmcache-metax-test`
3. Tests run automatically → result posted back to the PR as a commit status

Check **Settings → Webhooks → Recent Deliveries** on GitHub to see each event and Jenkins' response.
