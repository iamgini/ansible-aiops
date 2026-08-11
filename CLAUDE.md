# CLAUDE.md - Ansible AIOps Project

This file provides guidance to Claude Code when working with the Ansible AIOps / MCP integration project.

## Project Overview

This project implements **intelligent event-driven automation** using:
- **Ansible Event-Driven Automation (EDA)** for event processing and routing
- **Model Context Protocol (MCP)** for AAP integration via `ansible.mcp` collection
- **AI-powered playbook generation** using pluggable backends (OpenAI-compatible, Lightspeed, Coder)
- **Smart job template matching** with LLM-based or Jinja-scored weighted algorithm (0-200+ points)
- **Event parsing** with auto-detection for generic/Prometheus and Elastic alert formats

All roles live in a local `internal.aiops` collection at `collections/ansible_collections/internal/aiops/`.

## Core Functionality

### 1. MCP-Based Job Template Matching

The centerpiece is `playbooks/intelligent-aiops-workflow.yml` using a **3-play architecture**:
- **Play 1** (localhost): Parses raw event payload, validates config, generates MCP manifest at runtime, adds `aap_mcp` host via `add_host`
- **Play 2** (aap_mcp): Queries AAP via `ansible.mcp.run_tool` with `name: job_templates_list`, stores results on localhost via `delegate_facts`
- **Play 3** (localhost): Runs `internal.aiops.aiops_mcp_matcher` role for scoring, launching, AI generation, and CaC
- Uses `ansible.mcp.mcp` connection plugin — MCP host is targeted directly (not via `delegate_to`)
- **Bearer token passed as `ansible_mcp_bearer_token` host var** in `add_host` (NOT via play-level `environment:` — connection plugin reads host vars before env vars are applied)
- Auto-launches highest-scoring template via `ansible.controller.job_launch` (using `controller_oauthtoken`) if score >= threshold

**Skip MCP**: Pass `-e "skip_mcp=true"` or `export SKIP_MCP=true` to bypass MCP query and go directly to AI playbook generation.

**Template Matching Modes** (`mcp_match_using_llm` toggle):

1. **LLM matching** (default, `mcp_match_using_llm=true`):
   - Trims templates to `{id, name, description}` to minimize token usage
   - Sends trimmed list + event context to OpenAI-compatible API
   - LLM returns: `{template_id, template_name, confidence, reason, suggested_extra_vars}`
   - Reuses same `GENERIC_AI_*` env vars as the playbook generator backend
   - Files: `tasks/llm_match.yml`

2. **Jinja scoring** (`mcp_match_using_llm=false`):
   - Event type in template name: **+50 points**
   - Service name in template name: **+40 points**
   - Hostname in template name: **+30 points**
   - Event type in description: **+20 points**
   - Service name in description: **+20 points**
   - Severity keyword match: **+15 points**
   - Tag match (each): **+10 points**
   - Files: `tasks/jinja_match.yml`

**MCP is optional** — when MCP is unavailable (no server configured, `skip_mcp=true`, or connection fails), the role automatically falls back to querying the AAP REST API directly (`/api/v2/job_templates/`). This requires `controller_host` and a bearer token. Disable fallback with `mcp_api_fallback=false`.

**MCP Matcher Role Task Structure** (`aiops_mcp_matcher`):
- `setup.yml` — MCP config validation, manifest generation, `add_host` for aap_mcp
- `query.yml` — MCP tool call on aap_mcp host, stores `_mcp_raw_response` on localhost via `delegate_facts`
- `query_api.yml` — API fallback: queries AAP REST API directly when MCP templates unavailable
- `main.yml` — Scoring (dispatches to `jinja_match.yml` or `llm_match.yml`), job launch if score >= threshold
- `jinja_match.yml` — Weighted Jinja2 scoring logic
- `llm_match.yml` — LLM-based matching via OpenAI-compatible API

### 2. Event Parsing System

Play 1 includes an event parsing subsystem that normalizes incoming payloads into standard `event_*` variables:

- **Auto-detection**: If `raw_payload` is provided (JSON string or dict), detects source by field presence (`alert_name` → elastic, else → generic)
- **Generic parser** (`event_parsers/generic.yml`): Handles Prometheus, webhooks, and generic payloads with fields like `event_type`, `host`, `severity`, `service`, `tags`
- **Elastic parser** (`event_parsers/elastic.yml`): Handles Elastic SIEM/Watcher alerts with fields like `alert_name`, `server_hostname`, `service_name`, `app_code`
- Both parsers output the same standard variables: `event_type`, `event_description`, `event_host`, `event_severity`, `event_service`, `event_tags`, `event_source`

When `raw_payload` is not provided, event variables must be passed directly via `-e` flags.

### 3. Event-Driven Automation

EDA rulebook at `rulebooks/intelligent-remediation.yml`:
- Listens for webhook events on port 5000 (`ansible.eda.webhook`)
- **7 rules** in priority order:
  - **Debug**: Catches payloads with `debug: true`
  - **Hello AAP**: Triggers "Hello World" job template for connectivity tests
  - **Case 1 - Disk Usage**: Launches "Remediate Disk Space" JT
  - **Case 2 - Service Down**: Launches "Restart Service" JT
  - **Case 3 - High CPU**: Launches "Investigate High CPU" JT
  - **Case 4 - Certificate Expiry**: Launches "Renew SSL Certificate" JT
  - **Case 5 - Unknown Event** (catch-all): Launches "AI Intelligence - Unknown Event Remediation" JT, which runs the `intelligent-aiops-workflow.yml` with `raw_payload`
- All rules use `run_job_template` — execution happens in AAP, the rulebook just routes events

### 4. Remediation Playbooks

Four concrete remediation playbooks launched by AAP job templates (Cases 1-4):
- `playbooks/remediation_disk-cleanup.yml` — Disk space remediation
- `playbooks/remediation_restart-service.yml` — Service restart with health checks
- `playbooks/remediation_investigate-cpu.yml` — CPU investigation and process analysis
- `playbooks/remediation_renew-certificate.yml` — SSL certificate renewal
- `playbooks/hello-world.yaml` — Debug/connectivity test playbook
- `playbooks/cac-create-jt.yml` — Standalone CaC: creates JT only (post code review, points to main branch)

### 5. AI Playbook Generation

Pluggable AI backends in `aiops_playbook_generator` role:
- Backends: `generic_api` (default, OpenAI-compatible), `lightspeed_api`, `coder_api`
- Dynamic include: `backend_{{ ai_backend }}.yml`
- **SpecDD guardrails**: `files/remediation-guardrails.sdd` defines org-wide safety rules injected into every LLM prompt via shared `tasks/build_prompt.yml`
- Custom guardrails: override with `-e "guardrails_spec_path=/path/to/custom.sdd"`
- **Validation + retry**: `tasks/validate_playbook.yml` runs yamllint, syntax-check, and ansible-lint; `tasks/generate_with_retry.yml` retries generation with error feedback (up to `ai_max_retries`, default 3). Validation is skipped by default (`ai_skip_validation=true`)
- Git operations via `ansible.scm` (git_retrieve + git_publish)
- Pushes to review branch: `aiops/<event_type>-<HHMMSS>`
- **AI review step** (optional, `ai_review_enabled=true`): After generation, a second AI pass reviews the playbook for security, idempotency, best practices, and pushes an improved version to `<branch>_review`. Supports separate model/API config (`AI_REVIEW_MODEL`, `AI_REVIEW_API_URL`, `AI_REVIEW_API_TOKEN`).

**Playbook Generator Role Task Structure** (`aiops_playbook_generator`):
- `main.yml` — Orchestrates the generation pipeline
- `build_prompt.yml` — Constructs LLM prompt with event context and guardrails
- `backend_generic_api.yml` — OpenAI-compatible API backend
- `backend_lightspeed_api.yml` — Red Hat Automation Code Assistant backend
- `backend_coder_api.yml` — Coder + Claude Code backend
- `generate_with_retry.yml` — Recursive retry with validation feedback
- `validate_playbook.yml` — yamllint, syntax-check, ansible-lint validation
- `git_push.yml` — Clone repo, commit generated playbook, push to review branch
- `ai_review.yml` — Optional second AI pass that reviews and pushes improved playbook to `<branch>_review`

### 6. CaC Resource Creation

`aiops_cac_manager` role creates AAP resources using `ansible.controller` modules:
- **Shared project** with `allow_override: true` — one project, many JTs
- **Per-event JT** with `scm_branch` set to `cac_jt_scm_branch` (defaults to review branch; override to `main` for post-merge)
- **Per-event WF** with Approval → Run JT nodes (optional, `cac_create_workflow=true` default)
- Authenticates via bearer token (preferred) or username/password
- **Auto-launch**: After creating the workflow, automatically launches it if `aap_auto_launch_workflow=true` (default)
- **Post-review mode**: Set `cac_create_workflow=false` to create JT only (no workflow). Used by `cac-create-jt.yml`.

**CaC workflow toggle** (`cac_after_code_review`, default `true` in main workflow):
- `true`: CaC is skipped in the main workflow. Run `playbooks/cac-create-jt.yml` after reviewing and merging code to main.
- `false`: CaC runs inline (existing behavior — creates JT + WF immediately).

**CaC Manager Role Task Structure** (`aiops_cac_manager`):
- `main.yml` — Orchestrates authentication, resource creation, and launch
- `authenticate.yml` — Bearer token or username/password authentication
- `create_resources.yml` — Creates project, job template, and optionally workflow template
- `launch_workflow.yml` — Auto-launches the created workflow (when `cac_create_workflow=true`)

## Environment Setup

### Required Environment Variables

```bash
# MCP Server Configuration (REQUIRED for template matching)
export AAP_MCP_SERVER_URL="https://aap.example.com:8448/job_management/mcp"
export AAP_BEARER_TOKEN="your_aap_oauth2_token_here"
```

### AI/LLM Backend Variables

```bash
# Generic AI API (OpenAI-compatible: OpenAI, Azure OpenAI, vLLM, Ollama, LiteLLM)
export GENERIC_AI_API_URL="http://localhost:11434/v1/chat/completions"
export GENERIC_AI_API_TOKEN="your_api_token_here"
export GENERIC_AI_MODEL="gpt-4"
export GENERIC_AI_VALIDATE_CERTS="false"

# Select AI backend (default: generic_api)
export AI_BACKEND="generic_api"   # Options: generic_api, lightspeed_api, coder_api

# LLM-based template matching (default: true)
export MCP_MATCH_USING_LLM="true"

# Skip validation of generated playbooks (default: true)
export AI_SKIP_VALIDATION="true"

# AI review step — second AI pass reviews generated playbook (default: false)
export AI_REVIEW_ENABLED="false"
export AI_REVIEW_MODEL="gpt-4"           # defaults to GENERIC_AI_MODEL
export AI_REVIEW_API_URL=""              # defaults to GENERIC_AI_API_URL
export AI_REVIEW_API_TOKEN=""            # defaults to GENERIC_AI_API_TOKEN

# Red Hat Automation Code Assistant (alternative backend)
export LIGHTSPEED_URL="http://localhost:8000/api/v0/ai/generations/"
export LIGHTSPEED_TOKEN="${AAP_BEARER_TOKEN}"

# Coder backend (alternative backend)
export CODER_URL="https://coder.example.com"
```

### Git Integration Variables

```bash
export GIT_TOKEN="ghp_your_github_token_here"
export GIT_REMOTE_URL="https://github.com/iamgini/ansible-ai-generated-playbooks.git"
export GIT_USERNAME="aiops-bot"
export GIT_EMAIL="aiops@example.com"
export GIT_DEFAULT_BRANCH="main"
export GIT_REVIEW_BRANCH_PREFIX="aiops"
export GIT_PLAYBOOK_DIR="playbooks"
export GIT_COMMIT_AUTHOR="AIOps Playbook Generator"
export GIT_SSL_VERIFY="true"
```

### AAP Controller / CaC Variables

```bash
# Direct Controller API Access
export CONTROLLER_HOST="https://controller.example.com"
export CONTROLLER_USERNAME="admin"
export CONTROLLER_PASSWORD="password"
export CONTROLLER_VERIFY_SSL="false"

# CaC Manager - AAP Resource Configuration
export AAP_ORGANIZATION="AIOps"
export AAP_AI_PROJECT="AIOps-AI-Generated-Playbooks"
export AAP_INVENTORY="Cac-Demo-Inventory"
export AAP_MACHINE_CREDENTIAL="AIOps-Machine-Credential"
export AAP_SCM_CREDENTIAL=""
export AAP_JT_PREFIX="AIOps-AI"
export AAP_WF_PREFIX="AIOps-WF-AI"
export AAP_APPROVAL_TIMEOUT="3600"
export AAP_AUTO_LAUNCH_WORKFLOW="true"
```

### EDA / Workflow Control Variables

```bash
# Skip MCP query, go directly to AI generation
export SKIP_MCP="false"

# Defer CaC to post-review (default: true — skip CaC in main workflow)
export CAC_AFTER_CODE_REVIEW="true"

# Create workflow in CaC (default: true; false = JT only)
export CAC_CREATE_WORKFLOW="true"

# API fallback when MCP is unavailable (default: true)
export MCP_API_FALLBACK="true"

# MCP bearer token (fallback for AAP_BEARER_TOKEN)
export MCP_BEARER_TOKEN="your_token_here"

# EDA Event Stream (AAP 2.7+ gateway-routed webhook)
export EDA_EVENT_STREAM_URL="https://aap.example.com:443/eda-event-streams/api/eda/v1/external_event_stream/<uuid>/post/"
export EDA_BASIC_AUTH="edatest:your_password"
```

### Installation

```bash
# 1. Install required collections
ansible-galaxy collection install -r collections/requirements.yml

# 2. Copy environment template and configure
cp .env.example .env
# Edit .env with your credentials

# 3. Test the integration
./test-mcp-integration.sh
```

## Common Commands

### Testing MCP Integration

```bash
# Standalone MCP connectivity test (queries job templates via MCP)
ansible-navigator run tests/test-mcp-query.yml -m stdout

# Run test script (checks connectivity, collections, executes sample playbook)
./test-mcp-integration.sh

# Manual playbook execution with sample event
ansible-navigator run playbooks/intelligent-aiops-workflow.yml -m stdout \
  -e "event_type=disk_alert" \
  -e "event_description='Disk usage at 95%'" \
  -e "event_service=nginx" \
  -e "event_host=web-server-01" \
  -e "event_severity=high" \
  -e 'event_tags=["web","production"]'

# With Jinja scoring (instead of default LLM matching)
ansible-navigator run playbooks/intelligent-aiops-workflow.yml -m stdout \
  -e "event_type=disk_alert" \
  -e "event_description='Disk usage at 95%'" \
  -e "event_host=web-server-01" \
  -e "event_severity=high" \
  -e "mcp_match_using_llm=false"

# Skip MCP, go directly to AI generation
ansible-navigator run playbooks/intelligent-aiops-workflow.yml -m stdout \
  -e "event_type=disk_alert" \
  -e "event_description='Disk usage at 95%'" \
  -e "event_host=web-server-01" \
  -e "skip_mcp=true"
```

### Running EDA Rulebook

```bash
# Start EDA rulebook (listens for events on port 5000)
ansible-rulebook \
  --rulebook rulebooks/intelligent-remediation.yml \
  --inventory inventory.yml \
  --verbose

# In another terminal, send test event
curl -sk -X POST "${EDA_EVENT_STREAM_URL}" \
  -H "Content-Type: application/json" \
  -u "${EDA_BASIC_AUTH}" \
  -d '{
    "type": "disk_alert",
    "source": "prometheus",
    "payload": {
      "hostname": "web-server-01",
      "service": "nginx",
      "severity": "high",
      "usage": 95,
      "tags": ["web", "production"]
    }
  }'
```

### Running Test Suite

```bash
# Run all test cases (requires EDA rulebook running + AAP configured)
tests/run-all-tests.sh

# Run individual test cases
tests/0-debug.sh           # Debug payload
tests/1-hello-aap.sh       # Hello AAP connectivity test
tests/2-disk-full.sh       # Case 1: Disk full remediation
tests/3-service-down.sh    # Case 2: Service down
tests/4-high-cpu.sh        # Case 3: High CPU
tests/5-cert-expiry.sh     # Case 4: Certificate expiry
tests/6-unknown-event.sh   # Case 5: Unknown event → AI workflow
tests/7-elastic-siem.sh    # Elastic SIEM alert parsing
tests/8-elastic-watcher.sh # Elastic Watcher alert parsing
```

### Code Assistant Playbook Generation

```bash
# Generate playbook using Code Assistant
ansible-navigator run generate-and-push.yml -m stdout \
  -e "event_type=high_cpu" \
  -e "event_description='CPU at 98%'" \
  -e "target_host=app-server-01"

# Skip Git push (local only)
ansible-navigator run generate-and-push.yml -m stdout --skip-tags git
```

## Project Structure

```
ansible-aiops/
├── playbooks/
│   ├── intelligent-aiops-workflow.yml     # Orchestrator (3-play: Setup → MCP Query → Score/Generate/CaC)
│   ├── remediation_disk-cleanup.yml       # Case 1: Disk space remediation
│   ├── remediation_restart-service.yml    # Case 2: Service restart
│   ├── remediation_investigate-cpu.yml    # Case 3: CPU investigation
│   ├── remediation_renew-certificate.yml  # Case 4: Certificate renewal
│   ├── hello-world.yaml                   # Debug/connectivity test
│   ├── cac-create-jt.yml                  # Standalone CaC: JT only (post code review)
│   ├── event_parsers/
│   │   ├── generic.yml                    # Generic/Prometheus/webhook parser
│   │   └── elastic.yml                    # Elastic SIEM/Watcher parser
│   └── templates/
│       └── mcp-manifest.json.j2           # Legacy MCP manifest template
├── rulebooks/
│   └── intelligent-remediation.yml        # EDA rulebook (7 rules, webhook on port 5000)
├── collections/
│   ├── requirements.yml                   # Collection dependencies (no version pinning)
│   └── ansible_collections/
│       ├── internal/aiops/                # Local collection (v1.0.0)
│       │   ├── galaxy.yml
│       │   └── roles/
│       │       ├── aiops_mcp_matcher/     # MCP setup, query, scoring, job launch
│       │       │   ├── defaults/main.yml
│       │       │   ├── tasks/{main,setup,query,query_api,jinja_match,llm_match}.yml
│       │       │   └── templates/mcp-manifest.json.j2
│       │       ├── aiops_playbook_generator/  # AI-powered playbook generation
│       │       │   ├── defaults/main.yml
│       │       │   ├── files/remediation-guardrails.sdd
│       │       │   └── tasks/{main,build_prompt,backend_*,generate_with_retry,validate_playbook,git_push}.yml
│       │       └── aiops_cac_manager/     # AAP resource creation (JT, WF, project)
│       │           ├── defaults/main.yml
│       │           ├── tasks/{main,authenticate,create_resources,launch_workflow}.yml
│       │           └── templates/{project,job_template,workflow_template}.yml.j2
│       └── ansible/mcp/                   # Vendored ansible.mcp collection
├── tests/
│   ├── run-all-tests.sh                   # Run all test cases sequentially
│   ├── {0..8}-*.sh                        # Individual test scripts (debug through elastic-watcher)
│   ├── *.json                             # Test fixtures (11 JSON payloads)
│   ├── test-mcp-query.yml                 # Standalone MCP connectivity test
│   └── TESTING-CURL-EVENTS.md             # Testing documentation
├── docs/
│   ├── ARCHITECTURE.md                    # System architecture diagrams
│   ├── EDA-MCP-INTEGRATION.md             # Complete integration guide
│   ├── SCORING-ALGORITHM.md               # Scoring algorithm details
│   ├── QUICKSTART.md                      # 5-minute quick start
│   ├── DEPLOYMENT-GUIDE.md                # Full deployment guide
│   ├── AAP-JOB-TEMPLATES-SETUP.md         # Required AAP job templates setup
│   ├── MODULAR-ARCHITECTURE.md            # Local collection refactoring notes
│   ├── INTELLIGENT-REMEDIATION-QUICKSTART.md  # Remediation system quickstart
│   ├── REMEDIATION-PLAYBOOKS-SUMMARY.md   # Summary of all 4 remediation playbooks
│   ├── SPECDD-GUARDRAILS.md               # SpecDD guardrails documentation
│   ├── CODER-INTEGRATION.md               # Coder + Claude Code backend docs
│   └── archive/                           # Archived/legacy documentation
├── deploy/
│   └── aap-credential-types.yml           # Custom AAP credential types (MCP, AI API, Git)
├── ansible.cfg                            # Sets collections_path=./collections
├── ansible-navigator.yml                  # Navigator config (EE image, env passthrough)
├── inventory.yml                          # Inventory with MCP vars
├── generate-and-push.yml                  # Code Assistant integration playbook
├── test-mcp-integration.sh                # Automated testing
├── .env.example                           # Environment template
├── .pre-commit-config.yaml                # gitleaks pre-commit hook
├── TODO.md                                # Future development roadmap
├── LICENSE                                # MIT license
├── .gitignore                             # Git ignore rules
└── README.md                              # Project overview
```

## Key Collections

This project depends on (defined in `collections/requirements.yml`, no version pinning):

- **ansible.mcp** — MCP client for AAP integration (also vendored locally in `collections/`)
- **ansible.utils** — Utility functions (auto-installed as dependency of ansible.mcp)
- **ansible.scm** — Git operations (git_retrieve, git_publish)
- **ansible.eda** — Event-driven automation
- **ansible.controller** — AAP controller modules (project, job_template, workflow, job_launch)
- **ansible.platform** — AAP platform integration (optional)

Install all: `ansible-galaxy collection install -r collections/requirements.yml`

## Deploying Custom Credential Types

The project includes 3 custom AAP credential types in `deploy/aap-credential-types.yml`:

| Credential Type | Injected Env Vars | Purpose |
|---|---|---|
| AIOps - MCP Bearer Token | `MCP_BEARER_TOKEN`, `AAP_MCP_SERVER_URL` | MCP server authentication |
| AIOps - Generic AI API | `GENERIC_AI_API_TOKEN`, `GENERIC_AI_API_URL`, `GENERIC_AI_MODEL` | AI playbook generation backend |
| AIOps - Git Token | `GIT_TOKEN`, `GIT_REMOTE_URL`, `GIT_USERNAME`, `GIT_EMAIL` | Generated playbook git push |

Deploy to AAP:
```bash
ansible-navigator run deploy/aap-credential-types.yml -m stdout \
  -e "controller_host=https://aap.example.com" \
  -e "controller_username=admin" \
  -e "controller_password=secret"
```

After deploying, create credential instances in AAP UI and attach them to the AIOps job template.

## Navigator Configuration

`ansible-navigator.yml` passes the following env vars through to the execution environment:
- `AAP_MCP_SERVER_URL`, `AAP_BEARER_TOKEN`, `MCP_BEARER_TOKEN`
- `GENERIC_AI_API_URL`, `GENERIC_AI_API_TOKEN`, `GENERIC_AI_MODEL`, `GENERIC_AI_VALIDATE_CERTS`

**Note**: `LIGHTSPEED_*`, `GIT_*`, and `CONTROLLER_*` vars are NOT in the passthrough list. If using those backends with `ansible-navigator`, add them to the `environment-variables.pass` list in `ansible-navigator.yml`.

## Development Workflows

### Modifying the Scoring Algorithm

The matcher role supports two modes (controlled by `mcp_match_using_llm`, default `true`):

**LLM matching** (default): Edit `collections/ansible_collections/internal/aiops/roles/aiops_mcp_matcher/tasks/llm_match.yml` to modify the prompt or response parsing. Uses `GENERIC_AI_*` env vars.

**Jinja scoring**: Edit `collections/ansible_collections/internal/aiops/roles/aiops_mcp_matcher/tasks/jinja_match.yml` to adjust weights.

Test changes:
```bash
# LLM matching (default)
ansible-navigator run playbooks/intelligent-aiops-workflow.yml -m stdout \
  -e "event_type=test" -e "event_description=test" -e "event_host=test" -vv

# Jinja scoring
ansible-navigator run playbooks/intelligent-aiops-workflow.yml -m stdout \
  -e "event_type=test" -e "event_description=test" -e "event_host=test" \
  -e "mcp_match_using_llm=false" -vv
```

### Adding New Event Parsers

Create a new parser file in `playbooks/event_parsers/` (e.g., `datadog.yml`) and update the source detection logic in `playbooks/intelligent-aiops-workflow.yml` Play 1.

### Adding New EDA Rules

Edit `rulebooks/intelligent-remediation.yml`. New rules must be placed **above** the catch-all "Unknown Event" rule:

```yaml
rules:
  - name: Your new rule
    condition: event.payload.custom_field == "value"
    action:
      run_job_template:
        name: "Your Template Name"
        organization: "AIOps"
```

Test:
```bash
ansible-rulebook --rulebook rulebooks/intelligent-remediation.yml -v
```

### Creating Custom Event Sources

Add to rulebook:

```yaml
sources:
  - name: Custom Kafka source
    ansible.eda.kafka:
      host: kafka.example.com
      port: 9092
      topic: custom-events
      
  - name: Custom file watcher
    ansible.eda.file:
      path: /var/log/custom.log
      pattern: "ERROR"
```

## MCP Server Configuration

The AAP MCP Server (separate service) should be configured with:

**Minimal `aap-mcp.yaml`:**
```yaml
services:
  controller:
    base_url: https://controller.example.com
    enabled: true
    toolsets:
      - job_management
      - inventory_management

authentication:
  type: oauth2
  token_env: BEARER_TOKEN_OAUTH2_AUTHENTICATION

server:
  port: 3000
  allow_write_operations: false  # Set true for auto-launch
```

## Security Considerations

### Token Management

- **NEVER commit tokens to git** — Use `.env` files (already in `.gitignore`)
- Store bearer tokens in environment variables or secret management systems
- Rotate tokens regularly (AAP UI → Users → Tokens → Recreate)
- Use read-only tokens by default; enable write operations only when needed
- Pre-commit hook (gitleaks) configured in `.pre-commit-config.yaml`

### MCP Server Security

- **Read-only by default**: `allow_write_operations: false`
- **RBAC enforcement**: MCP inherits AAP user permissions
- **Use HTTPS in production**: Configure TLS for MCP server
- **Network isolation**: MCP server should be internal-only
- **Audit logging**: Enable AAP activity stream to track MCP actions

### Auto-Launch Safety

Auto-launching templates is powerful but risky. Guidelines:

1. **Test extensively** before enabling auto-launch
2. **Set high confidence threshold** (≥100 points recommended)
3. **Limit scope** — only auto-launch for specific event types/severities
4. **Require approval** — CaC workflows include an approval node by default
5. **Monitor outcomes** — track success/failure rates
6. **Implement rollback** — have undo playbooks ready

Example safe auto-launch (uses `ansible.controller.job_launch` with oauthtoken):

```yaml
- name: Auto-launch only if very high confidence
  ansible.controller.job_launch:
    controller_host: "{{ controller_host }}"
    controller_oauthtoken: "{{ controller_oauthtoken }}"
    validate_certs: false
    job_template: "{{ best_match.name }}"
    limit: "{{ event_host }}"
  when:
    - best_match is defined
    - best_match.score >= 120  # Very high bar
    - event_severity != 'critical'  # Never auto for critical
    - "'production' not in event_tags"  # Never auto for prod
```

## Troubleshooting

### MCP Connection Issues

**Symptom**: "Cannot connect to MCP server"

**Solutions**:
1. Check if MCP server is running: `curl $AAP_MCP_SERVER_URL`
2. Verify environment variable: `echo $AAP_MCP_SERVER_URL`
3. Check network/firewall rules
4. Review MCP server logs

### Authentication Failures

**Symptom**: "Authentication failed" or "401 Unauthorized"

**Solutions**:
1. Verify token hasn't expired (AAP UI → Users → Tokens)
2. Check token has correct scope (read vs. write)
3. Ensure user has RBAC permissions for job templates
4. Test token with curl:
   ```bash
   curl -H "Authorization: Bearer $AAP_BEARER_TOKEN" \
        https://controller.example.com/api/v2/job_templates/
   ```

### No Templates Matched

**Symptom**: Playbook returns empty recommendations

**Solutions**:
1. Verify job templates exist in AAP
2. Check RBAC — user needs access to templates
3. Review template naming conventions
4. Lower matching threshold in playbook
5. Add more tags to events

### Low Match Scores

**Symptom**: All templates score < 50 points

**Solutions**:
1. Improve template naming (include service names, keywords)
2. Add detailed descriptions to templates
3. Adjust scoring weights in playbook
4. Enrich event data with more context

## Testing

### Unit Testing

```bash
# Syntax check
ansible-navigator run playbooks/intelligent-aiops-workflow.yml -m stdout --syntax-check

# Check mode (won't actually query AAP)
ansible-navigator run playbooks/intelligent-aiops-workflow.yml -m stdout --check

# Verbose output for debugging
ansible-navigator run playbooks/intelligent-aiops-workflow.yml -m stdout -vvv
```

### Integration Testing

```bash
# Full integration test (requires MCP server running)
./test-mcp-integration.sh

# Run all EDA test cases (requires EDA rulebook running + AAP configured)
tests/run-all-tests.sh

# Individual test cases
tests/2-disk-full.sh       # Sends case1-disk-full.json
tests/7-elastic-siem.sh    # Sends elastic-siem-alert.json

# Manual event submission to EDA via Event Stream
curl -sk -X POST "${EDA_EVENT_STREAM_URL}" \
  -H "Content-Type: application/json" \
  -u "${EDA_BASIC_AUTH}" \
  -d @tests/case1-disk-full.json
```

### Test Fixtures

11 JSON test payloads in `tests/`:
- `debug.json`, `hello-aap.json` — Debug and connectivity tests
- `case1-disk-full.json` through `case4-cert-expiry.json` — Known remediation cases
- `case-unknown-event.json` — Unknown event → AI workflow
- `case-elastic-customer.json`, `case-elastic-customer-raw.json` — Elastic customer alerts
- `elastic-siem-alert.json`, `elastic-watcher-alert.json` — Elastic alert formats

### Performance Testing

Monitor key metrics:
- MCP query latency (should be < 2 seconds)
- Scoring computation time (should be < 1 second)
- End-to-end event-to-recommendation time (should be < 5 seconds)

## Important Notes

- **AAP Version**: Requires AAP 2.6.4+ for MCP server support
- **Python Version**: Requires Python 3.10+ for ansible.mcp collection
- **Ansible Version**: Requires Ansible Core 2.16+ for EDA features
- **MCP Server**: Must be installed separately (see AAP documentation)
- **Token Expiration**: AAP tokens expire; rotate regularly
- **RBAC Impact**: User permissions determine visible templates
- **Event Schema**: Events should follow consistent schema for best matching
- **Template Naming**: Descriptive names dramatically improve matching accuracy
- **Score Tuning**: Adjust weights based on your environment and template naming patterns
- **Auto-Launch Risk**: Only enable after extensive testing with high confidence thresholds
- **Navigator Env Passthrough**: Only a subset of env vars are passed to the EE — check `ansible-navigator.yml` if a variable isn't being picked up

## Resources

### Internal Documentation

- **docs/QUICKSTART.md** — Get up and running in 5 minutes
- **docs/INTELLIGENT-REMEDIATION-QUICKSTART.md** — Full remediation system quickstart
- **docs/DEPLOYMENT-GUIDE.md** — Complete deployment guide
- **docs/AAP-JOB-TEMPLATES-SETUP.md** — Setting up the 5 required AAP job templates
- **docs/ARCHITECTURE.md** — System architecture and deployment patterns
- **docs/EDA-MCP-INTEGRATION.md** — Comprehensive integration guide
- **docs/SCORING-ALGORITHM.md** — Detailed scoring algorithm reference
- **docs/MODULAR-ARCHITECTURE.md** — Local collection architecture explanation
- **docs/REMEDIATION-PLAYBOOKS-SUMMARY.md** — Summary of all remediation playbooks
- **docs/SPECDD-GUARDRAILS.md** — SpecDD guardrails for AI generation
- **docs/CODER-INTEGRATION.md** — Coder + Claude Code backend documentation
- **tests/TESTING-CURL-EVENTS.md** — Comprehensive testing guide with curl examples

### External Links

- [ansible.mcp Collection](https://github.com/ansible-collections/ansible.mcp) — MCP client documentation
- [AAP MCP Server](https://github.com/ansible/aap-mcp-server) — MCP server for AAP
- [Red Hat Blog: MCP for AAP](https://www.redhat.com/en/blog/it-automation-agentic-ai-introducing-mcp-server-red-hat-ansible-automation-platform)
- [Model Context Protocol Spec](https://modelcontextprotocol.io/)
- [Ansible EDA Documentation](https://ansible.readthedocs.io/projects/rulebook/)

## Contributing

When modifying this project:

1. **Test thoroughly** — Run `./test-mcp-integration.sh` after changes
2. **Update documentation** — Keep docs in sync with code changes
3. **Maintain scoring logic** — Document any weight adjustments
4. **Add examples** — Include event examples for new use cases
5. **Security review** — Never commit credentials or tokens
6. **Version collections** — Update `collections/requirements.yml` if adding dependencies
7. **Add test fixtures** — Create JSON payloads in `tests/` for new event types

## Support

For issues or questions:

1. Check the troubleshooting section above
2. Review logs with `-vvv` verbosity
3. Consult the comprehensive documentation in `docs/`
4. Test connectivity with `./test-mcp-integration.sh`
5. Verify environment variables are set correctly
