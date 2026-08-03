# Modular AIOps Architecture

This document describes the refactored modular architecture for the Intelligent AIOps workflow.

## Overview

The workflow has been refactored from a monolithic playbook into a **local Ansible collection** (`internal.aiops`) with **reusable roles** and **pluggable AI backends**.

**Before (Monolithic):**
- Single large playbook (~300 lines)
- Hardcoded logic for MCP + Lightspeed API
- Separate playbook for Coder integration
- Difficult to maintain and extend

**After (Collection-based):**
- Orchestrator playbook (90 lines)
- Local collection `internal.aiops` with 3 roles
- Roles referenced via FQCN (`internal.aiops.aiops_mcp_matcher`)
- Pluggable AI backends (Lightspeed, Generic API, or Coder)
- Easy to add new AI backends

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Playbook: intelligent-aiops-workflow.yml               │
│  (Orchestrator - 90 lines)                              │
└────────────┬────────────────────────────────────────────┘
             │
             ▼
┌────────────────────────────────────────────────────────┐
│  Collection: internal.aiops                            │
├────────────────────────────────────────────────────────┤
│  Role: aiops_mcp_matcher                               │
│  ├─ Query AAP via MCP                                  │
│  ├─ Score job templates                                │
│  ├─ Launch job if score ≥ threshold                    │
│  └─ Set: mcp_completed = true/false                    │
├────────────────────────────────────────────────────────┤
│  Role: aiops_playbook_generator                        │
│  ├─ Validate ai_backend variable                       │
│  ├─ Include backend-specific tasks:                    │
│  │    ├─ backend_lightspeed_api.yml                    │
│  │    ├─ backend_generic_api.yml                       │
│  │    └─ backend_coder_api.yml                         │
│  ├─ Push to review branch (ansible.scm)                │
│  └─ Set: ai_git_review_branch                          │
├────────────────────────────────────────────────────────┤
│  Role: aiops_cac_manager                               │
│  ├─ Shared project (allow_override=true)               │
│  ├─ Per-event JT (scm_branch=review branch)            │
│  ├─ Per-event WF (Approval → Run JT)                  │
│  └─ Uses ansible.controller modules directly           │
└────────────────────────────────────────────────────────┘
```

## Directory Structure

```
ansible-aiops/
├── ansible.cfg                           # collections_paths = ./collections
├── playbooks/
│   └── intelligent-aiops-workflow.yml    # Main orchestrator
│
├── collections/ansible_collections/internal/aiops/
│   ├── galaxy.yml                        # Collection metadata
│   └── roles/
│       ├── aiops_mcp_matcher/            # Role 1: MCP integration
│       │   ├── defaults/main.yml
│       │   ├── tasks/main.yml
│       │   └── meta/main.yml
│       │
│       ├── aiops_playbook_generator/     # Role 2: AI generation (pluggable)
│       │   ├── defaults/main.yml
│       │   ├── meta/main.yml
│       │   ├── files/
│       │   │   └── remediation-guardrails.sdd  # SpecDD safety rules for AI generation
│       │   └── tasks/
│       │       ├── main.yml              # Backend selector
│       │       ├── build_prompt.yml       # Shared prompt builder (reads .sdd spec)
│       │       ├── backend_lightspeed_api.yml
│       │       ├── backend_generic_api.yml
│       │       ├── backend_coder_api.yml
│       │       ├── validate_playbook.yml
│       │       ├── git_push.yml          # Uses ansible.scm (git_retrieve + git_publish)
│       │       └── generate_with_retry.yml
│       │
│       └── aiops_cac_manager/            # Role 3: CaC management
│           ├── defaults/main.yml
│           ├── meta/main.yml
│           └── tasks/
│               ├── main.yml
│               ├── authenticate.yml
│               ├── create_resources.yml  # Uses ansible.controller modules directly
│               └── launch_workflow.yml
│
└── docs/
    ├── CODER-INTEGRATION.md
    └── MODULAR-ARCHITECTURE.md           # This file
```

## Roles

### Role 1: `internal.aiops.aiops_mcp_matcher`

**Purpose**: Query AAP via MCP to find and launch existing job templates.

**Inputs** (from playbook):
- `event_type`, `event_description`, `event_host`, `event_severity`
- `event_service`, `event_tags` (optional)
- `mcp_server_url` (from `AAP_MCP_SERVER_URL` env), `mcp_bearer_token` (from `AAP_BEARER_TOKEN` env)
- `mcp_confidence_threshold` (default: 100)

**Outputs** (set_fact):
- `mcp_completed` (bool) - true if job was launched, false otherwise
- `mcp_action` - "aap_job_launched" or "no_match"
- `mcp_job_id`, `mcp_template_name`, `mcp_score` (if job launched)

**Logic**:
1. Query MCP server with event context
2. Score returned job templates (0-200+ points)
3. If best score ≥ threshold → Launch AAP job → Set `mcp_completed=true`
4. Otherwise → Set `mcp_completed=false` → Next role will generate playbook

### Role 2: `internal.aiops.aiops_playbook_generator`

**Purpose**: Generate Ansible playbooks using AI (pluggable backend), guided by SpecDD guardrails.

**Inputs** (from playbook):
- `event_type`, `event_description`, `event_host`, `event_severity`
- `ai_backend` - `"generic_api"` (default), `"lightspeed_api"`, or `"coder_api"`
- `guardrails_spec_path` - Path to custom `.sdd` guardrails file (optional, defaults to built-in)
- Backend-specific configs (URLs, tokens, etc.)

**Outputs** (set_fact):
- `ai_generation_completed` (bool)
- `ai_backend_used` - backend identifier
- `ai_playbook_filename` - Generated playbook filename
- `ai_git_pushed` (bool) - Whether playbook was pushed to git
- `ai_git_review_branch` - Review branch name (e.g., `aiops/disk-full-150303`)

**SpecDD Guardrails** (`files/remediation-guardrails.sdd`):

The role uses [Spec-Driven Development (SpecDD)](https://github.com/specdd/specdd) to inject safety guardrails into the LLM prompt. The `.sdd` spec defines org-wide rules that apply to ALL generated playbooks regardless of event type:

- **Must** rules: Use FQCN, check state before acting, be idempotent, report changes
- **Must not** rules: Delete user data, reboot without approval, use `rm -rf`, disable SELinux, modify firewall/SSH/user accounts
- **Forbids**: Specific dangerous patterns like `ansible.builtin.reboot` without approval checks

The shared `build_prompt.yml` task reads the spec, extracts the Must/Must-not/Forbids sections, and injects them into the LLM prompt before any backend sends it. All three backends use this shared prompt builder.

```
Event context + Guardrails spec → build_prompt.yml → generation_prompt → LLM backend
```

To customize guardrails for your organization:
```bash
# Use a custom guardrails file
ansible-navigator run playbooks/intelligent-aiops-workflow.yml -m stdout \
  -e "guardrails_spec_path=/path/to/my-org-guardrails.sdd" \
  -e "event_type=disk_alert" ...
```

**Git Workflow** (`git_push.yml`):
- Uses `ansible.scm.git_retrieve` to clone repo and create review branch
- Uses `ansible.scm.git_publish` to commit and push
- Branch naming: `<prefix>/<event_type>-<HHMMSS>` (e.g., `aiops/disk-full-150303`)
- Token passed via `origin.token` with `urlencode` filter

**Backends**:

#### Backend: `generic_api` (Default)
**File**: `tasks/backend_generic_api.yml`

**What it does**:
1. Build prompt from event context
2. Call OpenAI-compatible API (OpenAI, Azure OpenAI, vLLM, Ollama, LiteLLM)
3. Strip markdown fences from response
4. Push to review branch via `ansible.scm`

**Configuration**:
```yaml
ai_backend: "generic_api"
generic_api_url: "http://localhost:11434/v1/chat/completions"
generic_api_token: "{{ lookup('env', 'GENERIC_AI_API_TOKEN') }}"
generic_ai_model: "gpt-4"
git_remote_url: "https://github.com/org/repo.git"
git_token: "{{ lookup('env', 'GIT_TOKEN') }}"
```

#### Backend: `lightspeed_api`
**File**: `tasks/backend_lightspeed_api.yml`

**What it does**:
1. Build prompt from event context
2. Call Red Hat Automation Code Assistant API
3. Push to review branch via `ansible.scm`

**Configuration**:
```yaml
ai_backend: "lightspeed_api"
lightspeed_url: "http://localhost:8000/api/v0/ai/generations/"
lightspeed_token: "{{ lookup('env', 'LIGHTSPEED_TOKEN') }}"
git_remote_url: "https://github.com/org/repo.git"
git_token: "{{ lookup('env', 'GIT_TOKEN') }}"
```

#### Backend: `coder_api`
**File**: `tasks/backend_coder_api.yml`

**What it does**:
1. Check Coder CLI availability
2. Create Coder workspace from template
3. Wait for workspace to be "Running"
4. Build Claude Code prompt
5. Execute Claude Code via SSH into workspace
6. Verify playbook was generated and pushed
7. Cleanup workspace (optional)

**Configuration**:
```yaml
ai_backend: "coder"
coder_url: "https://coder.example.com"
coder_template_name: "ansible-remediation"
workspace_timeout: 600
auto_cleanup_workspace: true
git_remote_url: "https://github.com/org/repo.git"
```

## Usage

### Basic Usage (Default: Lightspeed Backend)

```bash
ansible-navigator run playbooks/intelligent-aiops-workflow.yml -m stdout \
  -e "event_type=disk_alert" \
  -e "event_description='Disk usage at 95% on /var'" \
  -e "event_host=web-server-01" \
  -e "event_severity=high"
```

**Environment variables needed**:
```bash
export AAP_MCP_SERVER_URL="https://aap.example.com:8448/job_management/mcp"
export AAP_BEARER_TOKEN="your_aap_token"
export LIGHTSPEED_URL="http://localhost:8000/api/v0/ai/generations/"
export LIGHTSPEED_TOKEN="your_lightspeed_token"
export GIT_TOKEN="ghp_your_github_token"
```

### Using Coder Backend

```bash
# Set backend via environment variable
export AI_BACKEND="coder"

# Or pass as extra var
ansible-navigator run playbooks/intelligent-aiops-workflow.yml -m stdout \
  -e "event_type=disk_alert" \
  -e "event_description='Disk usage at 95%'" \
  -e "event_host=web-server-01" \
  -e "event_severity=high" \
  -e "ai_backend=coder"
```

**Additional environment variables for Coder**:
```bash
export AI_BACKEND="coder"
export CODER_URL="https://coder.example.com"
export CODER_SESSION_TOKEN="your_coder_token"
export GIT_TOKEN="ghp_your_github_token"
```

### Skipping MCP (Force AI Generation)

```bash
# Skip MCP query
ansible-navigator run playbooks/intelligent-aiops-workflow.yml -m stdout \
  -e "event_type=test" \
  -e "event_description='Test AI generation'" \
  -e "event_host=localhost" \
  -e "event_severity=low" \
  -e "skip_mcp=true" \
  -e "ai_backend=generic_api"
```

### From EDA Rulebook

```yaml
# rulebooks/find-template-on-unmatched-event.yml
rules:
  - name: Catch-all for unknown events
    condition: event.type is defined
    action:
      run_playbook:
        name: playbooks/intelligent-aiops-workflow.yml
        extra_vars:
          event_type: "{{ event.type }}"
          event_description: "{{ event.payload.description }}"
          event_host: "{{ event.payload.hostname }}"
          event_severity: "{{ event.payload.severity }}"
          event_service: "{{ event.payload.service | default('') }}"
          event_tags: "{{ event.payload.tags | default([]) }}"
          ai_backend: "{{ lookup('env', 'AI_BACKEND') | default('generic_api') }}"
```

## Configuration

### Inventory Variables

**File**: `inventory.yml`

```yaml
all:
  hosts:
    localhost:
      ansible_connection: local
  vars:
    # AI Backend Selection (can also be set via env: AI_BACKEND)
    ai_backend: "generic_api"  # or "lightspeed_api" or "coder_api"
    
    # MCP Configuration
    mcp_server_url: "{{ lookup('env', 'AAP_MCP_SERVER_URL') }}"
    mcp_bearer_token: "{{ lookup('env', 'AAP_BEARER_TOKEN') }}"
    mcp_confidence_threshold: 100
    
    # Lightspeed Backend
    lightspeed_url: "{{ lookup('env', 'LIGHTSPEED_URL') }}"
    lightspeed_token: "{{ lookup('env', 'LIGHTSPEED_TOKEN') }}"
    
    # Coder Backend
    coder_url: "{{ lookup('env', 'CODER_URL') }}"
    coder_template_name: "ansible-remediation"
    workspace_timeout: 600
    auto_cleanup_workspace: true
    
    # Git Configuration (common to both backends)
    git_remote_url: "https://github.com/your-org/your-repo.git"
    git_token: "{{ lookup('env', 'GIT_TOKEN') }}"
    git_username: "{{ lookup('env', 'GIT_USERNAME') | default('aiops-bot') }}"
    git_email: "{{ lookup('env', 'GIT_EMAIL') | default('aiops@example.com') }}"
```

### Role Defaults

Roles have sensible defaults in `defaults/main.yml`. Override in inventory or playbook as needed.

**Override example**:
```yaml
- name: Execute AI generator with custom settings
  ansible.builtin.include_role:
    name: internal.aiops.aiops_playbook_generator
  vars:
    ai_backend: "coder"
    workspace_timeout: 1200  # 20 minutes instead of default 10
    auto_cleanup_workspace: false  # Keep workspace for inspection
```

## Workflow Examples

### Example 1: MCP Finds Match → AAP Job Launched

```
Input Event:
  type: disk_alert
  host: web-server-01
  severity: high

Step 1: aiops_mcp_matcher
  → Query MCP: Found "Disk Cleanup - Web Servers" (score: 120)
  → Score ≥ 100 (threshold)
  → Launch AAP job
  → Set: mcp_completed = true

Step 2: aiops_playbook_generator
  → SKIPPED (mcp_completed = true)

Output:
  ✅ AAP Job ID: 12345
  Template: "Disk Cleanup - Web Servers"
```

### Example 2: No MCP Match → Lightspeed Generates Playbook

```
Input Event:
  type: unknown_error
  host: app-server-01
  severity: medium

Step 1: aiops_mcp_matcher
  → Query MCP: No templates found (score: 0)
  → Score < 50 (minimum)
  → Set: mcp_completed = false

Step 2: aiops_playbook_generator (backend: generic_api)
  → Build prompt
  → Call OpenAI-compatible API
  → Receive playbook content
  → Clone repo via ansible.scm.git_retrieve
  → Create review branch: aiops/unknown-error-143022
  → Save to playbooks/unknown_error_app_server_01.yml
  → Push via ansible.scm.git_publish
  → Set: ai_generation_completed = true

Step 3: aiops_cac_manager
  → Create/update shared project (allow_override=true)
  → Create JT with scm_branch=aiops/unknown-error-143022
  → Create WF: Approval → Run JT

Output:
  ✅ Generated: playbooks/unknown_error_app_server_01.yml
  Git: Pushed to branch aiops/unknown-error-143022
  AAP: JT + WF created (approval required)
```

### Example 3: No MCP Match → Coder Generates Playbook

```
Input Event:
  type: service_crash
  host: db-server-01
  severity: critical

Step 1: aiops_mcp_matcher
  → Query MCP: Found "Restart Services" (score: 45)
  → Score < 50 (minimum)
  → Set: mcp_completed = false

Step 2: aiops_playbook_generator (backend: coder_api)
  → Check Coder CLI
  → Create workspace: aiops-service-crash-20260710-143022
  → Wait for "Running" status
  → SSH into workspace
  → Execute Claude Code
  → Claude Code: Generate + Lint + Commit + Push
  → Verify playbook exists
  → Cleanup workspace
  → Set: ai_generation_completed = true

Step 3: aiops_cac_manager
  → Create/update shared project (allow_override=true)
  → Create JT with scm_branch=review branch
  → Create WF: Approval → Run JT

Output:
  ✅ Generated: playbooks/service_crash_db_server_01.yml
  Workspace: Deleted (auto_cleanup = true)
  Git: Pushed to review branch
  AAP: JT + WF created (approval required)
```

## Adding New AI Backends

To add a new AI backend (e.g., "ollama", "openai"):

1. **Create backend tasks file**:
   ```bash
   touch collections/ansible_collections/internal/aiops/roles/aiops_playbook_generator/tasks/backend_ollama.yml
   ```

2. **Implement backend logic** (use shared `build_prompt.yml` for guardrails):
   ```yaml
   ---
   # Backend: Ollama (local LLM)
   
   - name: Build prompt from guardrails spec and event context
     ansible.builtin.include_tasks: build_prompt.yml
   
   - name: Call Ollama API
     ansible.builtin.uri:
       url: "http://localhost:11434/api/generate"
       method: POST
       body:
         model: "llama2"
         prompt: "{{ generation_prompt }}"
     register: ollama_response
   
   # ... validate, git clone, save, commit, push ...
   
   - name: Set generation results
     ansible.builtin.set_fact:
       ai_generation_completed: true
       ai_backend_used: "ollama"
       ai_playbook_filename: "{{ playbook_filename }}"
   ```

   **Important**: Always use `include_tasks: build_prompt.yml` instead of building prompts inline. This ensures the SpecDD guardrails are applied consistently across all backends.

3. **Update role main.yml**:
   ```yaml
   # collections/ansible_collections/internal/aiops/roles/aiops_playbook_generator/tasks/main.yml
   
   - name: Validate AI backend selection
     ansible.builtin.assert:
       that:
         - ai_backend in ['generic_api', 'lightspeed_api', 'coder_api', 'ollama_api']
   
   - name: Include backend tasks
     ansible.builtin.include_tasks: "backend_{{ ai_backend }}.yml"
   ```

4. **Add defaults**:
   ```yaml
   # collections/ansible_collections/internal/aiops/roles/aiops_playbook_generator/defaults/main.yml
   
   # Ollama Backend Configuration
   ollama_url: "{{ lookup('env', 'OLLAMA_URL') | default('http://localhost:11434', true) }}"
   ollama_model: "{{ lookup('env', 'OLLAMA_MODEL') | default('llama2', true) }}"
   ```

5. **Document usage**:
   ```bash
   export AI_BACKEND="ollama"
   ansible-navigator run playbooks/intelligent-aiops-workflow.yml -m stdout \
     -e "ai_backend=ollama" \
     -e "event_type=test" \
     ...
   ```

## Benefits of Modular Architecture

1. **Separation of Concerns**
   - MCP logic isolated in one role
   - AI generation logic in another
   - Backends in separate files

2. **Reusability**
   - Roles can be imported into other playbooks
   - Could become Ansible Collections in the future

3. **Maintainability**
   - Each role/backend is small and focused
   - Easy to find and fix bugs
   - Clear dependencies

4. **Extensibility**
   - Add new AI backends without touching MCP code
   - Add new MCP providers without touching AI code
   - Easy to test individual components

5. **Flexibility**
   - Switch backends via single variable
   - Override defaults per-playbook or per-invocation
   - Use roles independently if needed

## Migration from Old Playbooks

**Old playbooks** (deprecated):
- `intelligent-aiops-workflow.yml` (old monolithic)
- `intelligent-aiops-workflow-coder.yml` (separate Coder version)

**New playbook**:
- `intelligent-aiops-workflow.yml` (new modular)

**Migration steps**:
1. Update inventory with backend selection: `ai_backend: "lightspeed"` or `"coder"`
2. Update EDA rulebooks to use new playbook (same filename, no changes needed)
3. Test with both backends
4. Old playbooks were replaced - no action needed

**Breaking changes**: None! The new playbook accepts the same variables and produces the same results.

## Troubleshooting

### Role not found

```
ERROR! The role 'internal.aiops.aiops_mcp_matcher' was not found
```

**Solution**: Ensure `ansible.cfg` has the correct `collections_paths`:
```ini
[defaults]
collections_paths = ./collections:~/.ansible/collections:/usr/share/ansible/collections
```

### Backend validation failed

```
ERROR! Invalid ai_backend: unknown. Must be 'generic_api', 'lightspeed_api', or 'coder_api'
```

**Solution**: Set `ai_backend` to a valid value:
```bash
export AI_BACKEND="generic_api"
# or
ansible-navigator run ... -m stdout -e "ai_backend=lightspeed_api"
```

### Role variables undefined

```
ERROR! 'event_type' is undefined
```

**Solution**: Pass required variables to playbook:
```bash
ansible-navigator run playbooks/intelligent-aiops-workflow.yml -m stdout \
  -e "event_type=disk_alert" \
  -e "event_description='Disk full'" \
  -e "event_host=server-01" \
  -e "event_severity=high"
```

## Testing

### Test MCP Matcher Role Independently

```bash
# Create test playbook
cat > test_mcp_matcher.yml <<EOF
---
- hosts: localhost
  roles:
    - role: internal.aiops.aiops_mcp_matcher
      vars:
        event_type: "test"
        event_description: "Test event"
        event_host: "localhost"
        event_severity: "low"
EOF

ansible-navigator run test_mcp_matcher.yml -m stdout
```

### Test AI Generator Role Independently

```bash
# Test Lightspeed backend
cat > test_ai_generator.yml <<EOF
---
- hosts: localhost
  roles:
    - role: internal.aiops.aiops_playbook_generator
      vars:
        event_type: "test"
        event_description: "Test event"
        event_host: "localhost"
        event_severity: "low"
        ai_backend: "lightspeed"
EOF

ansible-navigator run test_ai_generator.yml -m stdout
```

## Future Enhancements

1. **Publish Collection**
   - Publish `internal.aiops` to Private Automation Hub
   - Version and distribute via `ansible-galaxy collection build`

2. **Add More Backends**
   - Ollama (local LLM)
   - OpenAI GPT-4
   - Custom models via InstructLab

3. **Enhanced MCP Scoring**
   - Machine learning-based scoring
   - Feedback loop from job success/failure

4. **Approval Workflows**
   - Slack/Teams approval for generated playbooks
   - Git PR-based review before deployment

5. **Metrics and Monitoring**
   - Prometheus metrics for MCP scores
   - Grafana dashboards for workflow success rates

## Resources

- **Main README**: [../README.md](../README.md)
- **Coder Backend Setup**: [CODER-INTEGRATION.md](CODER-INTEGRATION.md)
- **EDA Integration**: [EDA-MCP-INTEGRATION.md](EDA-MCP-INTEGRATION.md)
- **Project Guidance**: [../CLAUDE.md](../CLAUDE.md)

---

**Last Updated**: 2026-07-10

**Architecture Version**: 2.0 (Modular)
