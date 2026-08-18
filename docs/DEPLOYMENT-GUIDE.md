# Deployment Guide - AAP-Based Intelligent Remediation

## Related Projects

This deployment integrates with:
- **Red Hat Automation Code Assistant** (Lightspeed) - AI-powered playbook generator built into AAP 2.6+ (required for Case 5 - Unknown Events)
- **[AAP MCP Server](https://github.com/ansible/aap-mcp-server)** - Model Context Protocol server for AAP
- **[ansible.mcp Collection](https://github.com/ansible-collections/ansible.mcp)** - MCP client for Ansible
- **[redhat.ai Collection](https://console.redhat.com/ansible/automation-hub/)** - AI model configuration and serving (optional for advanced AI analysis)

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Event Sources                                 │
│              (Prometheus, Grafana, Custom)                       │
└────────────────────────┬────────────────────────────────────────┘
                         │ Webhook
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│              AAP - Event-Driven Ansible (EDA)                    │
│                                                                  │
│  Rulebook: intelligent-remediation.yml                          │
│  Event Stream (via AAP Gateway HTTPS)                           │
└────────────┬────────────────────────────────────────────────────┘
             │
    ┌────────┴──────────────────┬───────────────────┬────────────┐
    │                           │                   │            │
    ▼                           ▼                   ▼            ▼
┌────────┐              ┌────────────┐      ┌──────────┐  ┌──────────┐
│ Case 1 │              │  Case 2    │      │  Case 3  │  │  Case 4  │
│ Disk   │              │  Service   │      │  CPU     │  │  Cert    │
│ Full   │              │  Down      │      │  High    │  │  Expiry  │
└───┬────┘              └─────┬──────┘      └─────┬────┘  └─────┬────┘
    │                         │                   │             │
    ▼                         ▼                   ▼             ▼
┌────────────────────────────────────────────────────────────────┐
│                AAP Job Templates (1-4)                         │
│  Runs remediation playbooks on target hosts                   │
└────────────────────────────────────────────────────────────────┘
                                                                  │
                                                           ┌──────▼──────┐
                                                           │   Case 5    │
                                                           │   Unknown   │
                                                           │   Event     │
                                                           └──────┬──────┘
                                                                  │
                                                                  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│         AAP Job Template 5: AI Intelligence Workflow                     │
│                                                                          │
│  1. Query AAP MCP → Find matching templates                            │
│     ├─ MCP available → MCP query                                       │
│     ├─ MCP unavailable + mcp_api_fallback=true → AAP REST API query   │
│     ├─ Score ≥100? → Launch AAP job template                           │
│     └─ Score <50?  → Continue to step 2                                │
│                                                                          │
│  2. Call AI API → Generate playbook                                    │
│  3. (Optional) AI Review → LLM reviews generated playbook             │
│     └─ ai_review_enabled=true → second LLM pass for quality review    │
│  4. Push to Git → ansible-ai-generated-playbooks                       │
│  5. CaC: Create AAP job template from generated playbook               │
│     ├─ cac_after_code_review=true (default) → Skip CaC in workflow    │
│     │   └─ Run playbooks/cac-create-jt.yml later (after human review) │
│     └─ cac_after_code_review=false → CaC runs inline                  │
└─────────────────────────────────────────────────────────────────────────┘
```

## Deployment Components

### 1. AAP Components (Core)

| Component | Purpose | Status |
|-----------|---------|--------|
| **EDA Rulebook Activation** | Routes events to job templates | ✅ Ready |
| **Job Template 1-4** | Known event remediation | ⏸️ You create |
| **Job Template 5** | AI intelligence workflow | ✅ Ready |
| **Project** | Contains playbooks | ⏸️ You create |
| **Credentials** | AAP, Git, MCP access | ⏸️ You configure |

### 2. External Services

| Service | Purpose | Required For | Status |
|---------|---------|--------------|--------|
| **Red Hat Code Assistant (Lightspeed)** | AI playbook generation | Case 5 (unknown events) | ✅ Built into AAP 2.6+ |
| **AAP MCP Server** | Template intelligence | Case 5 (optional) | ⚠️ Optional |
| **Git Repository** | Store generated playbooks | Case 5 | ✅ Ready |
| **Red Hat AI** (optional) | Advanced incident analysis | Enhanced diagnostics | ⚠️ Optional |

### 3. No Local Execution Needed

❌ **NOT required:**
- Local ansible-navigator execution
- Local ansible-rulebook execution  
- Local Python environment
- Local collection installation

✅ **Everything runs in AAP!**

## Deployment Steps

### Phase 1: AAP Setup (Core Infrastructure)

#### Step 1.1: Create Remediation Playbooks

In your git repository:

```bash
# Create 4 remediation playbooks
# (See AAP-JOB-TEMPLATES-SETUP.md for examples)
vim playbooks/remediation_disk-cleanup.yml
vim playbooks/remediation_restart-service.yml
vim playbooks/remediation_investigate-cpu.yml
vim playbooks/remediation_renew-certificate.yml

# Commit and push
git add playbooks/remediation_*.yml
git commit -m "Add remediation playbooks for Cases 1-4"
git push
```

#### Step 1.2: Create AAP Project

**AAP UI → Projects → Add:**
- Name: `Remediation Playbooks`
- Organization: `Default`
- SCM Type: `Git`
- SCM URL: `https://github.com/your-org/remediation-playbooks`
- SCM Branch/Tag/Commit: `main`
- Update on Launch: ✅ Enabled

#### Step 1.3: Create AAP Job Templates 1-4

For each template, **AAP UI → Templates → Add → Job Template:**

**Template 1:**
- Name: `Remediate Disk Space`
- Job Type: `Run`
- Inventory: `Production Linux`
- Project: `Remediation Playbooks`
- Playbook: `playbooks/remediation_disk-cleanup.yml`
- Credentials: `Machine Credential`
- Prompt on Launch: `Limit`, `Extra Variables`

**Template 2:**
- Name: `Restart Service`
- (Same structure, different playbook)

**Template 3:**
- Name: `Investigate High CPU`
- (Same structure, different playbook)

**Template 4:**
- Name: `Renew SSL Certificate`
- (Same structure, different playbook)

#### Step 1.4: Test Job Templates Manually

Test via **AAP UI** → Templates → "Remediate Disk Space" → Launch:
- **Limit:** `test-server-01`
- **Extra Variables:**
  ```yaml
  event_severity: high
  ```

### Phase 2: AI Intelligence Setup (Case 5)

#### Step 2.1: Create ansible-aiops Project in AAP

**AAP UI → Projects → Add:**
- Name: `ansible-aiops`
- Organization: `Default`
- SCM Type: `Git`
- SCM URL: `https://github.com/iamgini/ansible-aiops` (or your fork)
- SCM Branch: `main`
- Update on Launch: ✅ Enabled

#### Step 2.2: Create Custom Credential Types

**Credential Type 1: AAP MCP**

**AAP UI → Credential Types → Add:**

**Name:** `AAP MCP`

**Input Configuration:**
```yaml
fields:
  - id: mcp_server_url
    type: string
    label: AAP MCP Server URL
    help_text: "e.g., https://aap.example.com:8448/job_management/mcp"
  - id: aap_bearer_token
    type: string
    label: AAP Bearer Token
    secret: true
```

**Injector Configuration:**
```yaml
env:
  AAP_MCP_SERVER_URL: "{{ mcp_server_url }}"
  AAP_BEARER_TOKEN: "{{ aap_bearer_token }}"
```

**Credential Type 2: Generic AI API**

**AAP UI → Credential Types → Add:**

**Name:** `Generic AI API`

**Input Configuration:**
```yaml
fields:
  - id: generic_ai_api_token
    type: string
    label: AI API Token
    secret: true
    help_text: "Bearer token for the AI API (OpenAI, Azure OpenAI, vLLM, Ollama, etc.)"
  - id: generic_ai_api_url
    type: string
    label: AI API URL
    help_text: "OpenAI-compatible chat completions endpoint URL"
  - id: generic_ai_model
    type: string
    label: AI Model
    help_text: "Model name (e.g., gpt-4, gpt-4o, llama3, mistral)"
required:
  - generic_ai_api_token
  - generic_ai_api_url
```

**Injector Configuration:**
```yaml
env:
  GENERIC_AI_API_TOKEN: "{{ generic_ai_api_token }}"
  GENERIC_AI_API_URL: "{{ generic_ai_api_url }}"
  GENERIC_AI_MODEL: "{{ generic_ai_model }}"
```

> **AI Review env vars:** If you enable the AI review step (`AI_REVIEW_ENABLED=true`),
> you can optionally set `AI_REVIEW_MODEL`, `AI_REVIEW_API_URL`, `AI_REVIEW_API_TOKEN`,
> and `AI_REVIEW_VALIDATE_CERTS` to use a different model or endpoint for review.
> When these are not set, the review step reuses the `GENERIC_AI_*` values above.
> Add any custom AI review env vars to the Generic AI API credential type injector
> or pass them as extra variables on the job template.

**Credential Type 3: Git SCM**

**AAP UI → Credential Types → Add:**

**Name:** `Git SCM`

**Input Configuration:**
```yaml
fields:
  - id: git_username
    type: string
    label: Git Username
  - id: git_token
    type: string
    label: Git Token or Password
    help_text: "Personal access token (GitHub/GitLab/Bitbucket) or password"
    secret: true
  - id: git_email
    type: string
    label: Git Email
```

**Injector Configuration:**
```yaml
env:
  GIT_TOKEN: "{{ git_token }}"
  GIT_USERNAME: "{{ git_username }}"
  GIT_EMAIL: "{{ git_email }}"
```

#### Step 2.3: Create Credentials

**AAP UI → Credentials → Add:**

**Credential 1:**
- Name: `AAP MCP`
- Credential Type: `AAP MCP`
- Fill in values:
  - MCP Server URL: `https://aap.example.com:8448/job_management/mcp`
  - AAP Bearer Token: `<your_token>`

**Credential 2:**
- Name: `Generic AI API`
- Credential Type: `Generic AI API`
- Fill in values:
  - AI API Token: `sk-...` (OpenAI), or your vLLM/Ollama token
  - AI API URL: `https://api.openai.com/v1/chat/completions` (or local endpoint)
  - AI Model: `gpt-4` (or `llama3`, `mistral`, etc.)

**Credential 3:**
- Name: `Git SCM`
- Credential Type: `Git SCM`
- Fill in values:
  - Git Username: `iamgini`
  - Git Token or Password: `ghp_...` (GitHub), `glpat-...` (GitLab), or app password (Bitbucket)
  - Git Email: `your_email@example.com`

#### Step 2.4: Create Job Template 5

**AAP UI → Templates → Add → Job Template:**
- Name: `AI Intelligence - Unknown Event Remediation`
- Job Type: `Run`
- Inventory: `localhost` (or create localhost inventory)
- Project: `ansible-aiops`
- Playbook: `playbooks/intelligent-aiops-workflow.yml`
- Credentials:
  - `Machine Credential` (localhost)
  - `AAP MCP`
  - `Generic AI API` (when using `ai_backend=generic_api`)
  - `Git SCM`
- Execution Environment: Default
- Variables:
  ```yaml
  lightspeed_url: "http://<lightspeed-host>:8000/api/v0/ai/generations/"
  lightspeed_token: "{{ lookup('env', 'LIGHTSPEED_TOKEN') }}"
  git_remote_url: "https://github.com/iamgini/ansible-ai-generated-playbooks"

  # MCP API fallback — query AAP REST API when MCP is unavailable (default: true)
  # mcp_api_fallback: true

  # AI review step — LLM reviews the generated playbook before commit (default: false)
  # ai_review_enabled: false

  # CaC after code review — skip inline CaC, run cac-create-jt.yml later (default: true)
  # cac_after_code_review: true

  # CaC workflow creation — set false to create JT only, no workflow (default: true)
  # cac_create_workflow: true
  ```
- Prompt on Launch: `Extra Variables`

#### Step 2.5: Test AI Intelligence Template

Test via **AAP UI** → Templates → "AI Intelligence - Unknown Event Remediation" → Launch → Add extra variables:
```yaml
event_type: database_slow_query
event_host: db-server-01
event_severity: medium
```

#### Step 2.6: Standalone CaC Job Template Creation

When `cac_after_code_review` is `true` (the default), the main workflow skips CaC
resource creation so a human can review the AI-generated playbook first. After
reviewing and merging the generated playbook into the `main` branch, run the
standalone CaC playbook to create the AAP job template:

```bash
ansible-navigator run playbooks/cac-create-jt.yml -m stdout \
  -e "event_type=database_slow_query" \
  -e "event_host=db-server-01" \
  -e "ai_playbook_filename=database_slow_query_db_server_01.yml"
```

`ai_playbook_filename` is required — it must match the exact filename JT1 generated.
When running as JT2 in an AAP workflow, this is passed automatically from JT1 via
`set_stats`. The playbook also parses `raw_payload` (same event parsers as the main
workflow) and skips CaC entirely if `mcp_completed=true` (template already matched
by JT1).

This playbook creates a job template pointing to the `main` branch (not a review
branch), so it is safe to launch repeatedly. Use it whenever:

- The main workflow deferred CaC (`cac_after_code_review=true`)
- You want to create a JT for a playbook that was already merged
- You need to recreate a JT without re-running the full AI pipeline

Control whether a workflow template is also created with `cac_create_workflow`
(default `true`). To create only the job template, pass
`-e "cac_create_workflow=false"`. The branch used for the JT SCM reference can
be overridden with `cac_jt_scm_branch` (defaults to `main`).

When `cac_create_workflow=false`, the JT is auto-launched after creation if
`aap_auto_launch_jt=true` (default).

### Phase 3: EDA Activation

#### Step 3.1: Create ansible-aiops Decision Environment Project

**AAP UI → Automation Decisions → Projects → Create:**
- Name: `ansible-aiops`
- Organization: `Default`
- SCM Type: `Git`
- SCM URL: `https://github.com/iamgini/ansible-aiops`
- SCM Branch: `main`
- SCM Update: ✅ On Launch

#### Step 3.2: Create Event Stream Credential

**AAP UI → Automation Decisions → Credentials → Create:**
- Name: `eda-webhook`
- Organization: `Default`
- Credential Type: `Basic Event Stream`
- Username/Password: Set your values

#### Step 3.3: Create Event Stream

**AAP UI → Automation Decisions → Event Streams → Create:**
- Name: `AIOps Webhook`
- Credential: `eda-webhook` (created above)

> **Important:** Copy the generated Event Stream URL. This is the HTTPS endpoint
> that external systems (Prometheus, Grafana, etc.) will send events to via the
> AAP gateway. Example format:
> `https://aap.example.com:443/eda-event-streams/api/eda/v1/external_event_stream/<uuid>/post/`

#### Step 3.4: Create Rulebook Activation

**AAP UI → Automation Decisions → Rulebook Activations → Create:**
- Name: `Intelligent Remediation`
- Description: `Routes events to AAP job templates based on type`
- Project: `ansible-aiops`
- Rulebook: `rulebooks/intelligent-remediation.yml`
- Decision Environment: `Default decision environment`
- Restart Policy: `On failure`
- Rulebook Activation Enabled: ✅ Yes

**Event Stream:**
- Select: `AIOps Webhook` (created above)

**Credentials:**
- Add AAP credential (for job template launches)

**Click:** `Create rulebook activation`

> **Note:** In AAP 2.7, events are received through Event Streams via the gateway (HTTPS).
> The rulebook's `ansible.eda.webhook` source with `port: 5000` is used internally
> by the EDA container — external traffic is routed through the Event Stream URL.

#### Step 3.5: Verify EDA is Running

**AAP UI:**
- Automation Decisions → Rulebook Activations → "Intelligent Remediation"
- Status should be "Running"
- Check the "History" tab for activation logs

### Phase 4: Integration & Testing

#### Step 4.1: Configure Event Sources

Point your monitoring systems to the EDA Event Stream URL (from Step 3.3):

**Prometheus Alertmanager:**
```yaml
receivers:
  - name: 'eda-webhook'
    webhook_configs:
      - url: 'https://aap.example.com:443/eda-event-streams/api/eda/v1/external_event_stream/<uuid>/post/'
        http_config:
          basic_auth:
            username: 'edatest'
            password: 'your_password'
```

**Grafana Alert:**
```
Webhook URL: https://aap.example.com:443/eda-event-streams/api/eda/v1/external_event_stream/<uuid>/post/
Auth: Basic (username/password from Event Stream credential)
```

#### Step 4.2: Test End-to-End Flow

See [Testing with curl - Sample Events](../tests/TESTING-CURL-EVENTS.md) for all test cases (debug, Cases 1-5, Elastic-style alerts).

## Monitoring & Operations

### View EDA Logs

**AAP UI:**
- Automation Decisions → Rulebook Activations → Intelligent Remediation
- Click "Instances" tab
- View logs for each event received

### View Job Executions

**AAP UI:**
- Jobs → All jobs
- Filter by Template name
- View execution history, logs, outputs

### Monitor Code Assistant API

```bash
# Check Code Assistant (Lightspeed) endpoint
curl -X POST "${LIGHTSPEED_URL}" \
  -H "Authorization: Bearer ${LIGHTSPEED_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"text": "ping"}'

# View Lightspeed logs (containerized AAP)
podman logs automation-controller -f
podman logs lightspeed-coding-assistant -f  # If separate container
```

### Git Repository Monitoring

```bash
# Check for new AI-generated playbooks
cd ansible-ai-generated-playbooks/
git pull
ls -lt playbooks/  # Latest first
```

## Troubleshooting

### Issue: EDA not receiving events

**Check:**
- Verify the rulebook activation is "Running" in AAP UI → Automation Decisions → Rulebook Activations
- Verify you are sending events to the correct Event Stream URL (HTTPS via gateway)
- Verify the Basic Auth credentials match the Event Stream credential
- Check the activation logs in the "History" tab

### Issue: Job template launch fails

**Check:**
- AAP credential attached to EDA activation?
- Job template name matches rulebook exactly?
- Job template enabled "Prompt on Launch" for variables?

### Issue: Code Assistant API not responding

**Check:**
```bash
# Verify Lightspeed service is running
podman ps | grep lightspeed

# Check Lightspeed logs
podman logs lightspeed-coding-assistant

# Verify AAP 2.6+ Lightspeed is enabled
# Check AAP admin interface → Settings → Lightspeed

# Test Maya API
curl http://<maya-host>:8000/api/v1/events/generate \
  -X POST -H "Content-Type: application/json" \
  -d '{"event_type": "test", "description": "test"}'
```

## Summary

**Deployment Checklist:**
- ✅ 4 Remediation playbooks created
- ✅ 4 AAP job templates created (Cases 1-4)
- ✅ AI Intelligence job template created (Case 5)
- ✅ EDA rulebook activated
- ✅ Event sources configured
- ✅ End-to-end testing completed
- ✅ MCP API fallback configured (`mcp_api_fallback` -- AAP REST API used when MCP unavailable)
- ✅ AI review step configured if needed (`ai_review_enabled`, plus optional `AI_REVIEW_*` env vars)
- ✅ CaC deferral strategy decided (`cac_after_code_review` -- default defers to post-review)
- ✅ Standalone CaC tested (`playbooks/cac-create-jt.yml` for post-review JT creation)

**Everything runs in AAP - no local execution needed!**
