# Quick Start Guide - MCP Integration with Ansible EDA

Get up and running with intelligent job template matching in 5 minutes.

## Prerequisites

- Ansible Automation Platform 2.6.4+
- AAP MCP Server installed and running
- Python 3.10+
- Ansible Core 2.16+
- **Red Hat Automation Code Assistant** (AAP 2.6+ Lightspeed) - For AI-powered playbook generation

## Related Projects

This project integrates with **Red Hat Automation Code Assistant** (AAP 2.6+ Lightspeed) for AI-powered playbook generation when handling unknown events. See the AAP 2.6 documentation for Lightspeed installation and setup instructions.

## Installation

### 1. Install Collections

```bash
ansible-galaxy collection install -r requirements.yml
```

This installs:
- `ansible.mcp` - MCP client
- `ansible.utils` - Utilities
- `ansible.eda` - Event-driven automation
- `ansible.controller` - AAP controller

### 2. Configure Environment

```bash
# Copy environment template
cp .env.example .env

# Edit with your values
export AAP_MCP_SERVER_URL="https://aap.example.com:8448/job_management/mcp"
export AAP_BEARER_TOKEN="your_aap_token_here"

# Optional: API fallback when MCP is unavailable (default: true)
export MCP_API_FALLBACK="true"
```

**Get your AAP token:**
1. Login to AAP web UI
2. Go to: Users → [Your Username] → Tokens
3. Click "Add" to create new token
4. Copy the token value

### 3. Verify Setup

```bash
# Run the test script
./test-mcp-integration.sh
```

If successful, you'll see:
- ✓ Environment variables set
- ✓ Required collections installed
- ✓ MCP server is reachable
- ✓ Playbook executed successfully

## Usage

### Option 1: Direct Playbook Execution

Find matching templates for a specific event:

```bash
ansible-navigator run playbooks/intelligent-aiops-workflow.yml -m stdout \
  -e "event_type=disk_alert" \
  -e "event_description='Disk usage at 95%'" \
  -e "event_service=nginx" \
  -e "event_host=web-server-01" \
  -e "event_severity=high" \
  -e 'event_tags=["web","production"]'
```

**Output:**
```
=== RECOMMENDED JOB TEMPLATES FOR EVENT ===
Event: disk_alert from unknown

1. Cleanup Disk Space - Web Servers (Score: 130)
   Description: Clean up disk space on web servers
   Project: Infrastructure Maintenance
   Inventory: Production Web Servers
   Template ID: 42

2. Nginx Service Recovery (Score: 90)
   ...
```

### Option 2: Event-Driven Automation

Run the EDA rulebook to continuously listen for events:

```bash
ansible-rulebook \
  --rulebook rulebooks/find-template-on-unmatched-event.yml \
  --inventory inventory.yml \
  --verbose
```

**Send a test event via Event Stream:**

```bash
export EDA_EVENT_STREAM_URL="https://aap.example.com:443/eda-event-streams/api/eda/v1/external_event_stream/<uuid>/post/"
export EDA_BASIC_AUTH="edatest:your_password"

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
      "tags": ["web", "production", "disk"]
    }
  }'
```

The rulebook will:
1. Try to match specific rules first
2. If no match, query AAP via MCP
3. Score all job templates
4. Display top recommendations

## Common Use Cases

### 1. Infrastructure Alerts

```bash
# Disk space alert
ansible-navigator run playbooks/intelligent-aiops-workflow.yml -m stdout \
  -e "event_type=disk_full" \
  -e "event_description='Disk at 98% on /var'" \
  -e "event_host=db-server-01" \
  -e "event_severity=critical"

# High CPU usage
ansible-navigator run playbooks/intelligent-aiops-workflow.yml -m stdout \
  -e "event_type=high_cpu" \
  -e "event_description='CPU usage at 95%'" \
  -e "event_host=app-server-03" \
  -e "event_severity=high"
```

### 2. Application Alerts

```bash
# Service down
ansible-navigator run playbooks/intelligent-aiops-workflow.yml -m stdout \
  -e "event_type=service_down" \
  -e "event_description='PostgreSQL service stopped'" \
  -e "event_service=postgresql" \
  -e "event_host=db-primary-01" \
  -e "event_severity=critical"

# Slow response time
ansible-navigator run playbooks/intelligent-aiops-workflow.yml -m stdout \
  -e "event_type=slow_response" \
  -e "event_description='API response time exceeds 5s'" \
  -e "event_service=api" \
  -e "event_host=api-server-01" \
  -e 'event_tags=["backend","production"]'
```

### 3. Security Alerts

```bash
# Security breach detected
ansible-navigator run playbooks/intelligent-aiops-workflow.yml -m stdout \
  -e "event_type=security_breach" \
  -e "event_description='Intrusion detected on firewall'" \
  -e "event_service=firewall" \
  -e "event_host=fw-01" \
  -e "event_severity=critical" \
  -e 'event_tags=["security","intrusion"]'
```

## Understanding Scores

The algorithm assigns points based on matches:

| Score | Interpretation | Recommendation |
|-------|---------------|----------------|
| 100+ | Excellent match | Auto-launch safe |
| 80-99 | Very good | Top recommendation |
| 50-79 | Good | Include in list |
| 25-49 | Weak | Use with caution |
| <25 | Poor | Consider new template |

## Customization

### Adjust Scoring Weights

Edit `collections/ansible_collections/internal/aiops/roles/aiops_mcp_matcher/tasks/jinja_match.yml` and modify the scoring section:

```yaml
# Example: Increase service name importance
{% if event_service_lower in name_lower %}
  {% set score = score + 80 %}  # Changed from 40
{% endif %}
```

### Auto-Launch High-Confidence Matches

The `aiops_mcp_matcher` role auto-launches when `best_match.score >= mcp_confidence_threshold` (default: 100).
To adjust, override the threshold variable:

```yaml
# In playbooks/intelligent-aiops-workflow.yml
- name: Execute template matcher (scoring and launch)
  ansible.builtin.include_role:
    name: internal.aiops.aiops_mcp_matcher
  vars:
    mcp_confidence_threshold: 120  # Raise bar for auto-launch
```

The role uses `ansible.controller.job_launch` (not MCP) for the actual launch.

## Troubleshooting

### "Cannot connect to MCP server"

- If `mcp_api_fallback=true` (the default), the workflow automatically falls back to the AAP REST API when the MCP server is unreachable. No action is needed unless you require MCP specifically.
- Check if MCP server is running: `curl $AAP_MCP_SERVER_URL`
- Verify URL is correct in `.env`
- Check firewall/network connectivity
- To disable automatic fallback: `-e "mcp_api_fallback=false"` or `export MCP_API_FALLBACK=false`

### "Authentication failed"

- Verify token is valid in AAP UI
- Check token hasn't expired
- Ensure user has read permissions for job templates

### "No templates found"

- Verify job templates exist in AAP
- Check RBAC - user needs access to templates
- Review template naming (improve descriptions for better matching)

### "No matches returned"

- Lower confidence threshold
- Make template names more descriptive
- Add more tags to events
- Review scoring algorithm weights

## Next Steps

1. **Read the full documentation:**
   - [EDA MCP Integration Guide](docs/EDA-MCP-INTEGRATION.md)
   - [Scoring Algorithm Details](docs/SCORING-ALGORITHM.md)

2. **Customize for your environment:**
   - Adjust scoring weights
   - Add custom event sources to EDA rulebook
   - Create naming conventions for job templates

3. **Integrate with monitoring:**
   - Configure Prometheus/Grafana to send webhooks
   - Set up ServiceNow/PagerDuty integration
   - Add Kafka/RabbitMQ event sources

4. **Enable automation:**
   - Set confidence threshold for auto-launch
   - Create approval workflows
   - Add rollback mechanisms

## Resources

- **GitHub:**
  - [ansible.mcp collection](https://github.com/ansible-collections/ansible.mcp)
  - [AAP MCP Server](https://github.com/ansible/aap-mcp-server)

- **Documentation:**
  - [Red Hat Blog: MCP for AAP](https://www.redhat.com/en/blog/it-automation-agentic-ai-introducing-mcp-server-red-hat-ansible-automation-platform)
  - [Model Context Protocol Spec](https://modelcontextprotocol.io/)

- **Community:**
  - [Ansible Forum](https://forum.ansible.com/)
  - [Reddit: r/ansible](https://reddit.com/r/ansible)

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review logs: `ansible-navigator run ... -m stdout -vvv`
3. Open an issue on the project repository
4. Ask on Ansible Forum

---

**Happy Automating! 🚀**
