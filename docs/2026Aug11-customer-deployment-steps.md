# Customer Deployment Steps — 2026-08-11 Changes

This document covers the deployment steps for the 6 new features added on 2026-08-11.
All changes are backward-compatible and gated by feature flags.

## Changes Summary

1. **AI review step** — after generation, a second AI pass reviews and pushes to `<branch>_review`
2. **Approval node** — AAP workflow pauses for human review
3. **Git merge flow** — user reviews in Git, merges to main (CI/CD external)
4. **User approves WF** — workflow continues after approval
5. **CaC simplification** — next JT in WF creates JT only, no nested WF
6. **MCP optional** — regex-based template matching fallback when MCP unavailable

---

## Step 1: Set Environment Variables

```bash
# Existing (already configured)
export AAP_MCP_SERVER_URL="https://aap.example.com:8448/job_management/mcp"
export AAP_BEARER_TOKEN="your_token"
export GENERIC_AI_API_URL="http://llm.example.com/v1/chat/completions"
export GENERIC_AI_API_TOKEN="your_api_key"
export GENERIC_AI_MODEL="gpt-4"

# New — AI Review (optional, uses same AI backend by default)
export AI_REVIEW_ENABLED="true"
# export AI_REVIEW_MODEL="gpt-4o"          # only if different from generator
# export AI_REVIEW_API_URL="..."            # only if different endpoint

# New — CaC deferred (default: true, already the right behavior)
export CAC_AFTER_CODE_REVIEW="true"

# New — MCP fallback (default: true, auto-queries REST API if MCP unavailable)
export MCP_API_FALLBACK="true"
```

## Step 2: Event Arrives — Main Workflow Runs

Either via EDA rulebook (automatic) or manual:

```bash
ansible-navigator run playbooks/intelligent-aiops-workflow.yml -m stdout \
  -e "event_type=disk_alert" \
  -e "event_description='Disk usage at 95%'" \
  -e "event_host=web-server-01" \
  -e "event_severity=high" \
  -e "event_service=nginx"
```

**What happens automatically:**

1. MCP queries AAP for matching templates (or falls back to REST API if MCP unavailable)
2. If a template scores >= threshold — launches it, done
3. If no match — AI generates remediation playbook — pushes to `aiops/disk_alert-143025`
4. AI review pass reviews the playbook — pushes improved version to `aiops/disk_alert-143025_review`
5. CaC is **skipped** (deferred to post-review)
6. Workflow summary prints both branch names

## Step 3: Human Reviews Code in Git

The operator now has two branches to compare:

- `aiops/disk_alert-143025` — AI-generated original
- `aiops/disk_alert-143025_review` — AI-reviewed improvements

The operator:

1. Reviews both branches in GitHub/GitLab
2. Customer CI/CD runs unit tests automatically
3. Merges the preferred version (or a combination) into `main`

## Step 4: Create Production Job Template in AAP

After code is merged to `main`, run the standalone CaC playbook:

```bash
ansible-navigator run playbooks/cac-create-jt.yml -m stdout \
  -e "event_type=disk_alert" \
  -e "event_host=web-server-01" \
  -e "ai_playbook_filename=disk_alert_web-server-01.yml"
```

**What this does:**

- Creates/updates the shared project in AAP (pointing to `main`)
- Creates a Job Template — **JT only, no workflow** — pointing to `main` branch
- The JT is ready to launch immediately or attach to an existing workflow

## Step 5: Run the Remediation

Launch the JT from AAP UI, or via CLI, or wire it into an existing workflow.

---

## Quick Reference — What Changed for the Operator

| Before (old flow) | After (today's changes) |
|---|---|
| AI generates — CaC creates JT + WF immediately | AI generates — AI reviews — human reviews in Git — then CaC |
| Single branch with generated code | Two branches: original + AI-reviewed |
| CaC creates WF with approval node inline | CaC creates JT only, post-merge |
| MCP required for template matching | MCP optional — auto-falls back to REST API |
| No second opinion on generated code | AI review catches security/idempotency issues |

## Turning Off New Features

All changes are optional. To revert to the previous behavior:

```bash
export AI_REVIEW_ENABLED="false"           # skip AI review
export CAC_AFTER_CODE_REVIEW="false"       # CaC runs inline (creates JT + WF)
export MCP_API_FALLBACK="false"            # no REST API fallback
```

## Feature Flags Reference

| Flag | Default | Env Var | Effect |
|------|---------|---------|--------|
| `ai_review_enabled` | `false` | `AI_REVIEW_ENABLED` | Second AI pass reviews generated playbook |
| `ai_review_model` | same as generator | `AI_REVIEW_MODEL` | Model for review (if different) |
| `ai_review_api_url` | same as generator | `AI_REVIEW_API_URL` | API endpoint for review (if different) |
| `ai_review_api_token` | same as generator | `AI_REVIEW_API_TOKEN` | API token for review (if different) |
| `cac_after_code_review` | `true` | `CAC_AFTER_CODE_REVIEW` | Skip CaC in main workflow, run post-review |
| `cac_create_workflow` | `true` | `CAC_CREATE_WORKFLOW` | Create WF in CaC (false = JT only) |
| `cac_jt_scm_branch` | review branch | — | Branch the JT points to (override to `main` post-merge) |
| `mcp_api_fallback` | `true` | `MCP_API_FALLBACK` | Query AAP REST API when MCP unavailable |

## New Files Added

| File | Purpose |
|------|---------|
| `roles/aiops_playbook_generator/tasks/ai_review.yml` | AI review step — reviews and pushes to `<branch>_review` |
| `roles/aiops_mcp_matcher/tasks/query_api.yml` | AAP REST API fallback — queries `/api/v2/job_templates/` |
| `playbooks/cac-create-jt.yml` | Standalone CaC — creates JT only, pointing to `main` |
