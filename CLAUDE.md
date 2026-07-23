# CLAUDE.md - Ansible AIOps Project

This file provides guidance to Claude Code when working with the Ansible AIOps / MCP integration project.

## Project Overview

This project implements **intelligent event-driven automation** using:
- **Ansible Event-Driven Automation (EDA)** for event processing
- **Model Context Protocol (MCP)** for AAP integration via `ansible.mcp` collection
- **AI-powered playbook generation** using Red Hat Automation Code Assistant
- **Smart job template matching** with weighted scoring algorithm (0-200+ points)

## Core Functionality

### 1. MCP-Based Job Template Matching

The centerpiece is `playbooks/intelligent-aiops-workflow.yml` using a **3-play architecture**:
- **Play 1** (localhost): Validates config, generates MCP manifest at runtime, adds `aap_mcp` host via `add_host`
- **Play 2** (aap_mcp): Queries AAP via `ansible.mcp.run_tool` with `name: job_templates_list`, stores results on localhost via `delegate_facts`
- **Play 3** (localhost): Runs `internal.aiops.aiops_mcp_matcher` role for scoring, launching, AI generation, and CaC
- Uses `ansible.mcp.mcp` connection plugin — MCP host is targeted directly (not via `delegate_to`)
- Bearer token injected via `environment: MCP_BEARER_TOKEN` for AAP credential type compatibility
- Auto-launches highest-scoring template via `ansible.controller.job_launch` if score >= threshold

**Scoring Algorithm:**
- Event type in template name: **+50 points**
- Service name in template name: **+40 points**
- Hostname in template name: **+30 points**
- Event type in description: **+20 points**
- Service name in description: **+20 points**
- Severity keyword match: **+15 points**
- Tag match (each): **+10 points**

### 2. Event-Driven Automation

EDA rulebook at `rulebooks/intelligent-remediation.yml`:
- Listens for events from webhooks, Kafka, or other sources
- Tries specific rules first (disk_alert, service_down, etc.)
- Falls back to MCP template finder when no rules match
- Enables automated incident response

### 3. AI Playbook Generation

Code Assistant integration in `generate-and-push.yml`:
- Calls Red Hat Code Assistant API with event details
- Generates playbooks using AI
- Commits and pushes to Git repository

## Environment Setup

### Required Environment Variables

```bash
# MCP Server Configuration (REQUIRED for template matching)
export AAP_MCP_SERVER_URL="https://aap.example.com:8448"
export AAP_BEARER_TOKEN="your_aap_oauth2_token_here"

# Red Hat Code Assistant (for AI playbook generation)
export LIGHTSPEED_URL="http://localhost:8000/api/v0/ai/generations/"
export LIGHTSPEED_TOKEN="${AAP_BEARER_TOKEN}"

# Git Integration (for Code Assistant playbook generation)
export GIT_TOKEN="ghp_your_github_token_here"

# Optional: Direct Controller API Access
export CONTROLLER_HOST="https://controller.example.com"
export CONTROLLER_USERNAME="admin"
export CONTROLLER_PASSWORD="password"
export CONTROLLER_VERIFY_SSL="false"
```

### Installation

```bash
# 1. Install required collections
ansible-galaxy collection install -r requirements.yml

# 2. Copy environment template and configure
cp .env.example .env
# Edit .env with your credentials

# 3. Test the integration
./test-mcp-integration.sh
```

## Common Commands

### Testing MCP Integration

```bash
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
```

### Running EDA Rulebook

```bash
# Start EDA rulebook (listens for events)
ansible-rulebook \
  --rulebook rulebooks/intelligent-remediation.yml \
  --inventory inventory.yml \
  --verbose

# In another terminal, send test event
curl -X POST http://localhost:5000/webhook \
  -H "Content-Type: application/json" \
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
│   └── intelligent-aiops-workflow.yml     # Orchestrator (MCP matcher + AI generator + CaC)
├── rulebooks/
│   └── intelligent-remediation.yml           # EDA rulebook
├── docs/
│   ├── ARCHITECTURE.md                   # System architecture diagrams
│   ├── EDA-MCP-INTEGRATION.md           # Complete integration guide
│   └── SCORING-ALGORITHM.md             # Scoring algorithm details
├── generated-playbooks/                  # Code Assistant-generated playbooks
├── requirements.yml                      # Collection dependencies
├── inventory.yml                         # Inventory with MCP vars
├── generate-and-push.yml                # Code Assistant integration playbook
├── test-mcp-integration.sh              # Automated testing
├── deploy/
│   └── aap-credential-types.yml         # Custom AAP credential types (MCP, AI API, Git)
├── .env.example                         # Environment template
├── .gitignore                           # Git ignore rules
├── QUICKSTART.md                        # 5-minute quick start
├── README.md                            # Project overview
└── CLAUDE.md                            # This file
```

## Key Collections

This project depends on:

- **ansible.mcp** (≥1.0.0) - MCP client for AAP integration
- **ansible.utils** (≥2.0.0) - Utility functions (dependency of ansible.mcp)
- **ansible.eda** (≥1.0.0) - Event-driven automation
- **ansible.controller** (≥4.5.0) - AAP controller interaction
- **ansible.platform** (≥1.0.0) - AAP platform integration

Install all: `ansible-galaxy collection install -r requirements.yml`

## Deploying Custom Credential Types

The project includes 3 custom AAP credential types in `deploy/aap-credential-types.yml`:

| Credential Type | Injected Env Vars | Purpose |
|---|---|---|
| AIOps - MCP Bearer Token | `MCP_BEARER_TOKEN`, `AAP_MCP_SERVER_URL` | MCP server authentication |
| AIOps - Generic AI API | `GENERIC_AI_API_TOKEN`, `GENERIC_AI_API_URL`, `GENERIC_API_MODEL` | AI playbook generation backend |
| AIOps - Git Token | `GIT_TOKEN`, `GIT_REMOTE_URL`, `GIT_USERNAME`, `GIT_EMAIL` | Generated playbook git push |

Deploy to AAP:
```bash
ansible-navigator run deploy/aap-credential-types.yml -m stdout \
  -e "controller_host=https://aap.example.com" \
  -e "controller_username=admin" \
  -e "controller_password=secret"
```

After deploying, create credential instances in AAP UI and attach them to the AIOps job template.

## Development Workflows

### Modifying the Scoring Algorithm

Edit `collections/ansible_collections/internal/aiops/roles/aiops_mcp_matcher/tasks/main.yml`, find the "Score and rank" task:

```yaml
- name: Score and rank job templates by relevance
  ansible.builtin.set_fact:
    scored_templates: >-
      {% set templates = [] %}
      {% for template in unique_matched_templates %}
        {% set score = 0 %}
        
        # Adjust weights here
        {% if event_type_lower in name_lower %}
          {% set score = score + 50 %}  # Change this value
        {% endif %}
        
        # Add new scoring rules here
        
      {% endfor %}
```

Test changes:
```bash
ansible-navigator run playbooks/intelligent-aiops-workflow.yml -m stdout -e "event_type=test" -e "event_description=test" -e "event_host=test" -vv
```

### Adding New EDA Rules

Edit `rulebooks/intelligent-remediation.yml`:

```yaml
rules:
  - name: Your new rule
    condition: event.payload.custom_field == "value"
    action:
      run_job_template:
        name: "Your Template Name"
        organization: "Default"
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

- **NEVER commit tokens to git** - Use `.env` files (already in `.gitignore`)
- Store bearer tokens in environment variables or secret management systems
- Rotate tokens regularly (AAP UI → Users → Tokens → Recreate)
- Use read-only tokens by default; enable write operations only when needed

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
3. **Limit scope** - only auto-launch for specific event types/severities
4. **Require approval** for critical operations
5. **Monitor outcomes** - track success/failure rates
6. **Implement rollback** - have undo playbooks ready

Example safe auto-launch (uses `ansible.controller.job_launch` after MCP scoring):

```yaml
- name: Auto-launch only if very high confidence
  ansible.controller.job_launch:
    controller_host: "{{ controller_host }}"
    controller_username: "{{ controller_username }}"
    controller_password: "{{ controller_password }}"
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
2. Check RBAC - user needs access to templates
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

# Manual event submission to EDA
curl -X POST http://localhost:5000/webhook \
  -H "Content-Type: application/json" \
  -d @tests/disk-alert.json
```

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

## Resources

### Internal Documentation

- **QUICKSTART.md** - Get up and running in 5 minutes
- **docs/EDA-MCP-INTEGRATION.md** - Comprehensive integration guide
- **docs/SCORING-ALGORITHM.md** - Detailed scoring algorithm reference
- **docs/ARCHITECTURE.md** - System architecture and deployment patterns
- **README.md** - Project overview and examples

### External Links

- [ansible.mcp Collection](https://github.com/ansible-collections/ansible.mcp) - MCP client documentation
- [AAP MCP Server](https://github.com/ansible/aap-mcp-server) - MCP server for AAP
- [Red Hat Blog: MCP for AAP](https://www.redhat.com/en/blog/it-automation-agentic-ai-introducing-mcp-server-red-hat-ansible-automation-platform)
- [Model Context Protocol Spec](https://modelcontextprotocol.io/)
- [Ansible EDA Documentation](https://ansible.readthedocs.io/projects/rulebook/)

## Contributing

When modifying this project:

1. **Test thoroughly** - Run `./test-mcp-integration.sh` after changes
2. **Update documentation** - Keep docs in sync with code changes
3. **Maintain scoring logic** - Document any weight adjustments
4. **Add examples** - Include event examples for new use cases
5. **Security review** - Never commit credentials or tokens
6. **Version collections** - Update `requirements.yml` if adding dependencies

## Support

For issues or questions:

1. Check the troubleshooting section above
2. Review logs with `-vvv` verbosity
3. Consult the comprehensive documentation in `docs/`
4. Test connectivity with `./test-mcp-integration.sh`
5. Verify environment variables are set correctly
