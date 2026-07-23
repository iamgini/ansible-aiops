# Intelligent Remediation - Quick Start Guide

## Overview

Complete event-driven intelligent remediation system:
- **Known events** → Direct AAP job template launch
- **Unknown events** → MCP search → Maya generation → Git push

## Architecture

```
                        ┌─────────────────────────────┐
                        │  Event Source               │
                        │  (Prometheus, webhook, etc) │
                        └──────────────┬──────────────┘
                                       │
                        ┌──────────────▼──────────────┐
                        │  EDA Rulebook (webhook:5000)│
                        │  intelligent-remediation.yml│
                        └──────────────┬──────────────┘
                                       │
                    ┌──────────────────┴──────────────────┐
                    │                                     │
            ┌───────▼─────────┐               ┌──────────▼─────────┐
            │ Known Event?    │               │ Unknown Event?     │
            │ (Case 1-4)      │               │ (Default)          │
            └───────┬─────────┘               └──────────┬─────────┘
                    │                                    │
        ┌───────────▼───────────┐           ┌────────────▼────────────┐
        │ execute-aap-job-      │           │ intelligent-aiops-      │
        │ template.yml          │           │ workflow.yml            │
        └───────────┬───────────┘           └────────────┬────────────┘
                    │                                    │
        ┌───────────▼───────────┐           ┌────────────▼────────────┐
        │ Launch AAP Job        │           │ 1. Query MCP            │
        │ Template Directly     │           │ 2. If score ≥100:       │
        │                       │           │    Launch AAP           │
        │ ✅ Done!              │           │ 3. If score <50:        │
        └───────────────────────┘           │    Call Maya API        │
                                            │ 4. Save to Git          │
                                            │                         │
                                            │ ✅ Done!                │
                                            └─────────────────────────┘
```

## Prerequisites

### 1. Required Services

- ✅ **Ansible Maya** - Running on port 8000
- ✅ **AAP/AWX** - Ansible Automation Platform (for Cases 1-4)
- ⚠️ **AAP MCP Server** - Optional (for unknown event intelligence)
- ⚠️ **Git Repository** - Optional (for storing generated playbooks)

### 2. AAP Job Templates (Cases 1-4)

Create these job templates in AAP:

| Case | Job Template Name | Purpose |
|------|------------------|---------|
| 1 | `Remediate Disk Space` | Clean up disk space |
| 2 | `Restart Service` | Restart failed services |
| 3 | `Investigate High CPU` | Troubleshoot CPU issues |
| 4 | `Renew SSL Certificate` | Renew expiring certificates |

**Note:** You can customize these names in the rulebook (lines 22, 41, 60, 79)

### 3. Environment Variables

```bash
# AAP/AWX Configuration (Required for Cases 1-4)
export CONTROLLER_HOST="https://controller.example.com"
export CONTROLLER_USERNAME="admin"
export CONTROLLER_PASSWORD="your_password"
export CONTROLLER_VERIFY_SSL="false"

# AAP MCP Server (Optional - for unknown events)
export AAP_MCP_SERVER_URL="https://aap.example.com:8448/job_management/mcp"
export AAP_BEARER_TOKEN="your_aap_oauth_token"

# Git Configuration (Optional - for storing generated playbooks)
export GIT_TOKEN="ghp_your_github_token"
export GIT_USERNAME="iamgini"
export GIT_EMAIL="your_email@example.com"

# Ansible Maya (Required for unknown events)
# Maya API runs on localhost:8000 by default
```

## Quick Start

### Step 1: Verify Prerequisites

```bash
cd ~/ansible-aiops

# Check Maya is running
curl http://localhost:8000/health

# Check required playbooks exist
ls -l playbooks/execute-aap-job-template.yml
ls -l playbooks/intelligent-aiops-workflow.yml

# Check rulebook exists
ls -l rulebooks/intelligent-remediation.yml
```

### Step 2: Install Dependencies

```bash
# Install required collections
ansible-galaxy collection install -r requirements.yml

# Required collections:
# - ansible.eda (for EDA webhook source)
# - ansible.controller (for AAP job launches)
```

### Step 3: Start EDA Rulebook

```bash
ansible-rulebook \
  --rulebook rulebooks/intelligent-remediation.yml \
  --inventory inventory.yml \
  --verbose
```

**Expected output:**
```
Waiting for events on port 5000...
```

### Step 4: Test with Events

Open a new terminal and send test events:

#### Test Case 1: High Disk Usage (Known Event)
```bash
curl -X POST http://localhost:5000/webhook \
  -H "Content-Type: application/json" \
  -d @tests/case1-disk-full.json
```

**Expected:**
- ✅ Rule matched: "High Disk Usage - Execute Known Remediation"
- ✅ AAP job template launched: "Remediate Disk Space"
- ✅ Job ID returned

#### Test Case 2: Service Down (Known Event)
```bash
curl -X POST http://localhost:5000/webhook \
  -H "Content-Type: application/json" \
  -d @tests/case2-service-down.json
```

**Expected:**
- ✅ Rule matched: "Service Down - Execute Known Remediation"
- ✅ AAP job template launched: "Restart Service"

#### Test Unknown Event (AI Workflow)
```bash
curl -X POST http://localhost:5000/webhook \
  -H "Content-Type: application/json" \
  -d @tests/case-unknown-event.json
```

**Expected:**
- ✅ Rule matched: "Unknown Event - Intelligent AI Workflow"
- ✅ MCP search executed (if configured)
- ✅ Maya playbook generated
- ✅ Playbook pushed to git (if GIT_TOKEN set)

## Configuration

### Customize AAP Job Template Names

Edit `rulebooks/intelligent-remediation.yml`:

```yaml
# Line 22 - Case 1: Disk Usage
aap_job_template: "YOUR_DISK_CLEANUP_TEMPLATE"

# Line 41 - Case 2: Service Down
aap_job_template: "YOUR_SERVICE_RESTART_TEMPLATE"

# Line 60 - Case 3: High CPU
aap_job_template: "YOUR_CPU_INVESTIGATION_TEMPLATE"

# Line 79 - Case 4: Certificate Expiry
aap_job_template: "YOUR_CERT_RENEWAL_TEMPLATE"
```

### Customize Event Matching

Edit the `condition` fields to match your event structure:

```yaml
# Example: Match custom alert field
- name: Custom Alert
  condition: event.payload.custom_alert_type == "my_alert"
  action:
    run_playbook:
      name: playbooks/execute-aap-job-template.yml
      extra_vars:
        aap_job_template: "My Custom Template"
```

### Adjust MCP Thresholds

Edit `playbooks/intelligent-aiops-workflow.yml`:

```yaml
vars:
  mcp_confidence_threshold: 100  # Auto-launch if score ≥ this
  mcp_minimum_score: 50          # Skip to Maya if score < this
```

## Monitoring

### View EDA Logs

```bash
# EDA outputs to console
# Look for:
# - "Rule matched: ..."
# - "Playbook execution started"
# - "Playbook execution completed"
```

### Check AAP Jobs

Check job status via **AAP UI** → Jobs (or Views → Jobs)

### Check Generated Playbooks

```bash
# View git repository
cd generated-playbooks/
git log --oneline

# Or check GitHub
https://github.com/iamgini/ansible-ai-generated-playbooks
```

## Troubleshooting

### Issue: AAP job launch fails

```
Error: "CONTROLLER_HOST not configured"
```

**Fix:** Export AAP environment variables:
```bash
export CONTROLLER_HOST="https://your-controller.com"
export CONTROLLER_USERNAME="admin"
export CONTROLLER_PASSWORD="password"
```

### Issue: Code Assistant API not responding

```
Error: "Connection refused to Code Assistant endpoint"
```

**Fix:** Verify AAP 2.6+ Lightspeed (Code Assistant) is deployed:
```bash
# Code Assistant is built into AAP 2.6+ - verify deployment
echo $LIGHTSPEED_URL
# Check AAP Lightspeed service status via AAP admin interface or logs
```

### Issue: Git push fails

```
Error: "Authentication failed"
```

**Fix:** Set valid GitHub token:
```bash
export GIT_TOKEN="ghp_your_valid_token"
export GIT_USERNAME="iamgini"
export GIT_EMAIL="your_email@example.com"
```

### Issue: No rules matching

**Check event payload structure:**
```bash
# View what EDA receives
# In EDA console, you'll see:
# "Event received: { ... }"
```

**Ensure event fields match rulebook conditions**

## Next Steps

1. ✅ Test all 4 known event cases
2. ✅ Test unknown event workflow
3. ⚠️ **Wait for your instruction** - AAP job template creation from generated playbooks
4. Configure production event sources (Prometheus, Grafana, etc.)
5. Fine-tune MCP confidence thresholds
6. Add more known event cases as needed

## Summary

You now have a complete intelligent remediation system:

- **4 known event types** → Direct AAP job launches
- **Unknown events** → MCP search → Maya generation → Git storage
- **Production-ready** → Just configure your AAP job templates!

**Current Status:**
- ✅ Rulebook created
- ✅ Action playbooks created  
- ✅ Test events created
- ✅ Ready to run
- ⏸️ **Waiting for your instruction** on AAP job template creation
