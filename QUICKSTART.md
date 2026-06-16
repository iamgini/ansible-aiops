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
export AAP_MCP_SERVER_URL="http://localhost:3000/mcp"
export AAP_BEARER_TOKEN="your_aap_token_here"
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
ansible-playbook playbooks/find-matching-job-template.yml \
  -e "event_type=disk_alert" \
  -e "event_service=nginx" \
  -e "event_hostname=web-server-01" \
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

**Send a test event:**

```bash
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
ansible-playbook playbooks/find-matching-job-template.yml \
  -e "event_type=disk_full" \
  -e "event_hostname=db-server-01" \
  -e "event_severity=critical"

# High CPU usage
ansible-playbook playbooks/find-matching-job-template.yml \
  -e "event_type=high_cpu" \
  -e "event_hostname=app-server-03" \
  -e "event_severity=high"
```

### 2. Application Alerts

```bash
# Service down
ansible-playbook playbooks/find-matching-job-template.yml \
  -e "event_type=service_down" \
  -e "event_service=postgresql" \
  -e "event_hostname=db-primary-01" \
  -e "event_severity=critical"

# Slow response time
ansible-playbook playbooks/find-matching-job-template.yml \
  -e "event_type=slow_response" \
  -e "event_service=api" \
  -e 'event_tags=["backend","production"]'
```

### 3. Security Alerts

```bash
# Security breach detected
ansible-playbook playbooks/find-matching-job-template.yml \
  -e "event_type=security_breach" \
  -e "event_service=firewall" \
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

Edit `playbooks/find-matching-job-template.yml` and modify the scoring section:

```yaml
# Example: Increase service name importance
{% if event_service_lower in name_lower %}
  {% set score = score + 80 %}  # Changed from 40
{% endif %}
```

### Auto-Launch High-Confidence Matches

Add to the playbook:

```yaml
- name: Auto-launch if high confidence
  ansible.mcp.run_tool:
    server_url: "{{ mcp_server_url }}"
    auth_token: "{{ aap_bearer_token }}"
    tool_name: "controller_api_v2_job_templates_launch"
    tool_arguments:
      id: "{{ (scored_templates | first).id }}"
  when:
    - scored_templates | length > 0
    - (scored_templates | first).score > 100
```

**Note:** Requires `ALLOW_WRITE_OPERATIONS=true` in MCP server config.

## Troubleshooting

### "Cannot connect to MCP server"

- Check if MCP server is running: `curl $AAP_MCP_SERVER_URL`
- Verify URL is correct in `.env`
- Check firewall/network connectivity

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
2. Review logs: `ansible-playbook ... -vvv`
3. Open an issue on the project repository
4. Ask on Ansible Forum

---

**Happy Automating! 🚀**
