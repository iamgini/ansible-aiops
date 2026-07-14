# EDA MCP Integration Guide

## Overview

This integration allows Ansible Event-Driven Automation (EDA) to use the Model Context Protocol (MCP) to query Ansible Automation Platform and intelligently find matching job templates when no specific rules match an incoming event.

## Architecture

```
┌─────────────┐      ┌──────────────┐      ┌─────────────┐      ┌─────────────┐
│   Event     │─────▶│  EDA         │─────▶│  Playbook   │─────▶│  AAP via    │
│   Source    │      │  Rulebook    │      │  (MCP)      │      │  MCP Server │
│  (webhook,  │      │              │      │             │      │             │
│   Kafka)    │      │              │      │             │      │             │
└─────────────┘      └──────────────┘      └─────────────┘      └─────────────┘
                            │
                            │ No rules matched
                            ▼
                     ┌──────────────┐
                     │  Fallback:   │
                     │  Find Best   │
                     │  Template    │
                     └──────────────┘
```

## Components

### 1. AAP MCP Server

The MCP server provides a programmatic interface to AAP APIs.

**Installation:**
```bash
# Via container (RHEL 9/10)
# Follow AAP 2.6.4+ installation guide for MCP server

# Set environment variables
export AAP_MCP_SERVER_URL="http://localhost:3000/mcp"
export AAP_BEARER_TOKEN="your_aap_token_here"
```

**Configuration (`aap-mcp.yaml`):**
```yaml
services:
  controller:
    base_url: https://controller.example.com
    enabled: true
    toolsets:
      - job_management
      - inventory_management
      - system_monitoring

  eda:
    base_url: https://eda.example.com
    enabled: true
    toolsets:
      - activations
      - rulebooks

authentication:
  type: oauth2
  token_env: BEARER_TOKEN_OAUTH2_AUTHENTICATION

server:
  port: 3000
  allow_write_operations: false  # Set to true for job launches
```

### 2. Ansible Collection Requirements

Install required collections:

```bash
ansible-galaxy collection install -r requirements.yml
```

**Key Collections:**
- `ansible.mcp` - MCP client modules
- `ansible.utils` - Utility functions
- `ansible.eda` - Event-driven automation
- `ansible.controller` - AAP controller interaction

### 3. Playbook: Find Matching Job Template

Located at: `playbooks/find-matching-job-template.yml`

**How it works:**

1. **Receives event data** from EDA via `ansible_eda.event` variable
2. **Queries AAP** via MCP server for all job templates
3. **Matches templates** against event attributes:
   - Event type
   - Service name
   - Hostname
   - Severity
   - Tags
4. **Scores templates** based on relevance (0-200+ points)
5. **Returns recommendations** ranked by score

**Scoring Algorithm:**
- Exact event type in name: +50 points
- Service name in template name: +40 points
- Hostname match: +30 points
- Event type in description: +20 points
- Service in description: +20 points
- Severity keywords: +15 points
- Tag matches: +10 points each

### 4. EDA Rulebook

Located at: `rulebooks/find-template-on-unmatched-event.yml`

**Workflow:**
1. Listen for events (webhook, Kafka, etc.)
2. Try to match specific rules first
3. If no match, run the template finder playbook
4. Display recommendations to operator

## Usage

### Running EDA with the Rulebook

**Using ansible-rulebook CLI:**
```bash
# Set required environment variables
export AAP_MCP_SERVER_URL="http://localhost:3000/mcp"
export AAP_BEARER_TOKEN="your_token_here"

# Run the rulebook
ansible-rulebook \
  --rulebook rulebooks/find-template-on-unmatched-event.yml \
  --inventory inventory.yml \
  --verbose
```

**Using ansible-navigator:**
```bash
ansible-navigator run \
  rulebooks/find-template-on-unmatched-event.yml \
  --mode stdout \
  --pae false
```

### Testing with Sample Events

**Send test webhook event:**
```bash
curl -X POST http://localhost:5000/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "type": "disk_alert",
    "source": "monitoring_system",
    "payload": {
      "hostname": "web-server-01",
      "service": "nginx",
      "severity": "high",
      "usage": 95,
      "tags": ["web", "production", "disk"]
    }
  }'
```

**Expected output:**
```
=== RECOMMENDED JOB TEMPLATES FOR EVENT ===
Event: disk_alert from monitoring_system

1. Cleanup Disk Space - Web Servers (Score: 130)
   Description: Clean up disk space on web servers
   Project: Infrastructure Maintenance
   Inventory: Production Web Servers
   Template ID: 42

2. Nginx Service Recovery (Score: 90)
   Description: Restart and recover nginx service
   Project: Service Management
   Inventory: Web Servers
   Template ID: 55

3. Disk Space Alert Response (Score: 70)
   Description: Generic disk space cleanup
   Project: Maintenance
   Inventory: All Servers
   Template ID: 23
```

### Running Standalone (Outside EDA)

You can run the playbook directly for testing:

```bash
ansible-navigator run playbooks/find-matching-job-template.yml -m stdout \
  -e "event_type=disk_alert" \
  -e "event_service=nginx" \
  -e "event_hostname=web-server-01" \
  -e "event_severity=high" \
  -e 'event_tags=["web","production"]'
```

## Configuration

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `AAP_MCP_SERVER_URL` | MCP server endpoint | Yes |
| `AAP_BEARER_TOKEN` | AAP OAuth2 token | Yes |

### Obtaining AAP Bearer Token

**Via AAP UI:**
1. Login to AAP
2. Navigate to: Users → [Your User] → Tokens
3. Create new token with appropriate scope
4. Copy token value

**Via API:**
```bash
curl -X POST https://aap.example.com/api/v2/tokens/ \
  -u username:password \
  -H "Content-Type: application/json" \
  -d '{"description": "EDA MCP Integration", "scope": "read"}'
```

## Advanced Usage

### Custom Scoring Logic

Modify the scoring section in `find-matching-job-template.yml`:

```yaml
- name: Score templates with custom logic
  ansible.builtin.set_fact:
    scored_templates: >-
      {% set templates = [] %}
      {% for template in unique_matched_templates %}
        {% set score = 0 %}
        
        # Add your custom scoring rules here
        {% if 'your_criteria' in template.name %}
          {% set score = score + 100 %}
        {% endif %}
        
        {% set _ = templates.append({'name': template.name, 'score': score}) %}
      {% endfor %}
      {{ templates | sort(attribute='score', reverse=True) }}
```

### Automatic Job Launch

To automatically launch the top-matched template (requires `ALLOW_WRITE_OPERATIONS=true`):

```yaml
- name: Launch best matching job template
  ansible.mcp.run_tool:
    server_url: "{{ mcp_server_url }}"
    auth_token: "{{ aap_bearer_token }}"
    tool_name: "controller_api_v2_job_templates_launch"
    tool_arguments:
      id: "{{ (scored_templates | first).id }}"
      extra_vars:
        triggered_by: "eda_mcp_automation"
        event_source: "{{ event_source }}"
  when:
    - scored_templates is defined
    - scored_templates | length > 0
    - (scored_templates | first).score > 80  # Confidence threshold
```

### Integration with Decision Environments

Include in your decision environment's `execution-environment.yml`:

```yaml
version: 3
dependencies:
  python: requirements.txt
  galaxy: requirements.yml
  system: bindep.txt

images:
  base_image:
    name: registry.redhat.io/ansible-automation-platform/de-minimal-rhel9:latest
```

## Troubleshooting

### MCP Connection Issues

```bash
# Test MCP server connectivity
ansible-navigator run playbooks/find-matching-job-template.yml -m stdout -vvv

# Check MCP tools available
ansible -m ansible.mcp.tools_info \
  -a "server_url=$AAP_MCP_SERVER_URL auth_token=$AAP_BEARER_TOKEN" \
  localhost
```

### EDA Rulebook Activation Fails with 404 on `/api/v2/config/`

**Symptom:**
```
ansible_rulebook.job_template_runner - ERROR - Error connecting to controller: 404, message='Not Found', url='https://aap.example.com/api/v2/config/'
ansible_rulebook.cli - ERROR - Terminating: 404, message='Not Found', url='https://aap.example.com/api/v2/config/'
```

**Cause:** Starting with AAP 2.5+, the unified gateway changed the controller API path from `/api/v2/` to `/api/controller/v2/`. The `ansible-rulebook` inside the Decision Environment is using the legacy path.

**Solutions:**

1. **Verify the AAP credential type** — EDA activations must use a credential of type **"Red Hat Ansible Automation Platform"** (gateway-aware), not the legacy "Controller" type. Check under AAP UI -> Credentials.

2. **Use OAuth2 token authentication** — The AAP gateway only supports OAuth2 tokens, not basic auth (username/password). Generate a token via AAP UI -> Users -> Tokens, or via the API:
   ```bash
   curl -X POST https://aap.example.com/api/gateway/v1/tokens/ \
     -u username:password \
     -H "Content-Type: application/json" \
     -d '{"description": "EDA Integration", "scope": "write"}'
   ```

3. **Update the Decision Environment** — Ensure the DE image contains a version of `ansible-rulebook` compatible with your AAP version. Check the version inside the DE:
   ```bash
   podman run --rm <your-de-image> pip show ansible-rulebook
   ```

4. **Verify the API path** — Confirm which path your AAP gateway responds to:
   ```bash
   # New gateway path (AAP 2.5+)
   curl -sk https://aap.example.com/api/controller/v2/config/

   # Legacy path (should return 404 on AAP 2.5+)
   curl -sk https://aap.example.com/api/v2/config/
   ```

**Reference:** [Red Hat Solution 7101444](https://access.redhat.com/solutions/7101444)

### Authentication Errors

- Verify token validity: Check expiration in AAP UI
- Confirm RBAC permissions: User needs read access to job templates
- Check MCP server logs for authentication failures

### No Templates Matched

- Lower the confidence threshold
- Add more generic matching keywords
- Review job template naming conventions
- Check if templates exist in AAP

## Security Considerations

1. **Token Storage**: Never commit tokens to git. Use environment variables or vault.
2. **Read-Only by Default**: MCP server should default to read-only mode.
3. **RBAC**: MCP inherits AAP user permissions - use service accounts with minimal privileges.
4. **Audit Logging**: Enable AAP activity stream to track MCP interactions.
5. **TLS**: Use HTTPS for MCP server in production.

## References

- [Ansible MCP Collection](https://github.com/ansible-collections/ansible.mcp)
- [AAP MCP Server](https://github.com/ansible/aap-mcp-server)
- [Red Hat Blog: MCP Server for AAP](https://www.redhat.com/en/blog/it-automation-agentic-ai-introducing-mcp-server-red-hat-ansible-automation-platform)
- [Model Context Protocol Specification](https://modelcontextprotocol.io/)
- [Ansible EDA Documentation](https://ansible.readthedocs.io/projects/rulebook/)
