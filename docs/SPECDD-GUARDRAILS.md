# SpecDD Guardrails for AI Playbook Generation

## Overview

The `aiops_playbook_generator` role uses [Spec-Driven Development (SpecDD)](https://github.com/specdd/specdd) to inject safety guardrails into every AI-generated remediation playbook. The guardrails are defined in a `.sdd` specification file that gets read at runtime and included in the LLM prompt.

This ensures that when an unknown event arrives and no existing AAP job template matches, the AI-generated playbook stays within your organization's safety boundaries — regardless of what the event is or which AI backend generates the code.

## The Problem

Without guardrails, the AI playbook generator sends a prompt like:

```
Create an Ansible playbook to remediate the following issue:
Event Type: disk_alert
Description: Disk usage at 95% on /var
Target Host: web-server-01
Severity: high

Requirements:
- Use FQCN
- Make the playbook idempotent
```

The LLM produces something plausible. But it has no idea about your organization's rules:
- Can it delete Docker images to free space? (Maybe not — the app team owns those.)
- Can it remove old kernel packages? (Maybe not — your change process requires approval.)
- Can it reboot the host if cleanup isn't enough? (Definitely not without explicit approval.)
- Can it use `rm -rf /var/log/*`? (Never.)

The AI handles the **unknown event**. The spec handles the **non-negotiable rules**.

## How It Works

```
┌─────────────────────────────────────────────────────────┐
│  build_prompt.yml (shared across all backends)          │
│                                                         │
│  1. Read remediation-guardrails.sdd                     │
│  2. Extract Must / Must not / Forbids sections          │
│  3. Inject into LLM prompt as "non-negotiable rules"    │
│  4. Append event context (type, host, severity, etc.)   │
│  5. Set generation_prompt fact                          │
└──────────────────────┬──────────────────────────────────┘
                       │
          ┌────────────┼────────────┐
          ▼            ▼            ▼
   generic_api   lightspeed   coder_api
   (OpenAI etc)  (Red Hat)    (Claude Code)
```

All three backends call `build_prompt.yml` first, then send `generation_prompt` to their respective LLM API. The guardrails are applied consistently regardless of backend.

## The Guardrails Spec

**Location**: `collections/ansible_collections/internal/aiops/roles/aiops_playbook_generator/files/remediation-guardrails.sdd`

The spec uses the [SpecDD format](https://github.com/specdd/specdd) with three key sections:

### Must (Required Behaviors)

Rules the AI **must follow** in every generated playbook:

| Rule | Why |
|------|-----|
| Target only the reported host | Prevent lateral damage to other systems |
| Use FQCN for all modules | Ansible best practice, avoids module name collisions |
| Prefer ansible.builtin modules | Reduce collection dependencies in generated code |
| Include block/rescue for error handling | Generated playbooks run unattended; errors must be caught |
| Check current state before making changes | Gather evidence first, act second |
| Be idempotent | Generated playbooks may run multiple times during an incident |
| Report what changed at the end | Operator needs a summary without reading every task |

### Must Not (Forbidden Actions)

Actions the AI **must never take**, regardless of event type:

| Rule | Why |
|------|-----|
| Delete user data, application data, or databases | Irreversible damage; cleanup must be targeted |
| Modify firewall rules or network configuration | Owned by network team; could isolate the host |
| Change SSH configuration or authentication | Could lock out operators during an incident |
| Modify user accounts, passwords, or sudo rules | Security-critical; requires change process |
| Reboot without explicit approval variable | Production hosts cannot be rebooted without operator consent |
| Stop services without recovery step | A stopped service during an incident makes it worse |
| Disable SELinux or AppArmor | Security control that must never be disabled |
| Download or execute scripts from the internet | Supply chain risk in generated automation |
| Use `rm -rf` or recursive force-delete | Catastrophic if path is wrong |

### Forbids (Specific Patterns)

Exact patterns that must never appear in generated playbooks:

- `ansible.builtin.reboot` without a conditional check for `allow_reboot` variable
- `ansible.builtin.raw` module
- `shell` tasks containing `rm -rf` or `find -delete` without path restrictions
- `selinux` module with `state=disabled`

## Configuration

### Default (Built-in Guardrails)

No configuration needed. The role uses `files/remediation-guardrails.sdd` automatically:

```bash
ansible-navigator run playbooks/intelligent-aiops-workflow.yml -m stdout \
  -e "event_type=disk_alert" \
  -e "event_description='Disk usage at 95%'" \
  -e "event_host=web-server-01" \
  -e "event_severity=high"
```

### Custom Guardrails

Override with a custom spec file for your organization:

```bash
ansible-navigator run playbooks/intelligent-aiops-workflow.yml -m stdout \
  -e "guardrails_spec_path=/opt/ansible/my-org-guardrails.sdd" \
  -e "event_type=disk_alert" \
  -e "event_description='Disk usage at 95%'" \
  -e "event_host=web-server-01" \
  -e "event_severity=high"
```

### No Guardrails (Not Recommended)

Point to a non-existent file. The prompt builder will fall back to generating without spec rules:

```bash
-e "guardrails_spec_path=/dev/null"
```

## Writing Custom Guardrails

Create a `.sdd` file following the SpecDD format. Only `Must`, `Must not`, and `Forbids` sections are injected into the prompt:

```sdd
Spec: ACME Corp Remediation Guardrails

Purpose:
  Safety rules for AI-generated playbooks at ACME Corp.

Must:
  Use ansible.builtin modules only (no third-party collections).
  Include a "Remediation by AIOps" comment at the top of every playbook.
  Send a notification to the #incidents Slack channel after completion.
  Tag all tasks with "aiops-generated".

Must not:
  Touch any host in the database tier.
  Modify /etc/sysctl.conf without kernel team approval.
  Install packages from external repositories.
  Use community.general modules (not approved in our environment).

Forbids:
  ansible.builtin.yum_repository with baseurl pointing outside internal mirrors
  Tasks with ignore_errors: true (mask failures in generated playbooks)
```

## Updating Guardrails After Incidents

When a production incident reveals a missing rule:

1. **Add the rule** to the `.sdd` spec:
   ```diff
    Must not:
      Delete user data, application data, or databases.
   +  Remove log files in /var/log/audit/ (required for compliance retention).
   ```

2. **Commit the change** — the spec is version-controlled alongside the role.

3. **Next AI generation** automatically picks up the new rule. No code changes to the role, backends, or prompt templates needed.

This is the key advantage over hardcoded prompts: the operations team maintains the guardrails without touching role code.

## How It Fits the AIOps Workflow

```
Unknown event arrives
    │
    ▼
MCP Matcher → no existing template found (score < threshold)
    │
    ▼
Playbook Generator:
    1. build_prompt.yml reads guardrails .sdd spec
    2. Constructs prompt = event context + guardrails + format rules
    3. Backend sends prompt to LLM
    4. LLM generates playbook FOR AN EVENT IT HAS NEVER SEEN
       ... but it CANNOT cross the organization's safety boundaries
    5. Validate generated playbook
    6. Push to review branch (not main)
    │
    ▼
CaC Manager → creates JT + Workflow in AAP → approval gate → run
```

The AI handles the unknown. The spec handles the non-negotiable.

## Related

- [Modular Architecture](MODULAR-ARCHITECTURE.md) — Role structure and backend details
- [SpecDD Framework](https://github.com/specdd/specdd) — Upstream SpecDD project
- [Architecture](ARCHITECTURE.md) — Full system architecture
