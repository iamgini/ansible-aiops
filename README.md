# Ansible AIOps Demo

Intelligent event-driven automation using Ansible EDA, MCP (Model Context Protocol), and AI-powered playbook generation.

**What is AIOps?** Combines AI, big data, and machine learning to augment/automate manual IT tasks, improving issue detection, root cause analysis, and system resolution. This implementation breaks the traditional "1,000 events = 1,000 rules" model with **"1 rule + AI inference"** handling dynamic scenarios.

## Features

- **AI-Powered Playbook Generation**: Uses Red Hat Automation Code Assistant (AAP 2.6+ Lightspeed) to generate playbooks based on events
- **Intelligent Job Template Matching**: MCP integration to find suitable AAP job templates for events
- **Event-Driven Automation**: EDA rulebooks for automated responses with multi-source support (Kafka, webhooks, file logs)
- **Git Integration**: Automatic commit and push of generated playbooks using `ansible.scm` collection
- **Multi-LLM Workflow**: Optional Red Hat AI for incident analysis + Code Assistant for remediation generation
- **Policy Enforcement**: Integration with Ansible Automated Policy as Code for guardrails

## Related Projects

This project integrates with:
- **Red Hat Automation Code Assistant** - AI-powered playbook generation (built into AAP 2.6+, required for Case 5 - Unknown Events)
- **[AAP MCP Server](https://github.com/ansible/aap-mcp-server)** - Model Context Protocol server for Ansible Automation Platform
- **[ansible.mcp Collection](https://github.com/ansible-collections/ansible.mcp)** - MCP client collection for Ansible
- **[redhat.ai Collection](https://console.redhat.com/ansible/automation-hub/)** - Optional AI model serving for incident analysis
- **[ansible.scm Collection](https://console.redhat.com/ansible/automation-hub/)** - Git operations for playbook commits

## Key Collections

| Collection | Purpose | Status |
|------------|---------|--------|
| `ansible.eda` | Event sources and rulebook engine | ✅ Required |
| `ansible.mcp` | MCP client for AAP integration | ✅ Required |
| `ansible.controller` | AAP configuration as code | ✅ Required |
| `ansible.scm` | Git commit automation | ✅ Required |
| `redhat.ai` | AI model serving (optional) | ⚠️ Optional |

## Setup

### 1. Install Dependencies

**Install required Ansible collections:**
```bash
ansible-galaxy collection install -r requirements.yml
```

**Required collections:**
- `ansible.mcp` - MCP client for AAP integration
- `ansible.utils` - Utility functions
- `ansible.eda` - Event-driven automation
- `ansible.controller` - AAP controller interaction

### 2. Configure Environment

**Copy and configure environment file:**
```bash
cp .env.example .env
# Edit .env with your credentials
```

**Required environment variables:**
```bash
# For MCP Integration
export AAP_MCP_SERVER_URL="http://localhost:3000/mcp"
export AAP_BEARER_TOKEN="your_aap_bearer_token_here"

# For Git Integration
export GIT_TOKEN="ghp_your_github_token_here"
```

### 3. Configure AAP MCP Server

See the [AAP MCP Server documentation](https://github.com/ansible/aap-mcp-server) for installation and configuration.

**Quick start:**
```bash
# Install MCP server (requires AAP 2.6.4+)
# Follow Red Hat documentation for your platform

# Start MCP server
# Server runs on port 3000 by default
```

## Usage

### Playbook Generation (Maya)

**Generate playbook using Maya:**
```bash
ansible-playbook generate-and-push.yml
```

**With custom event (override variables):**
```bash
ansible-playbook generate-and-push.yml \
  -e "event_type=high_cpu" \
  -e "event_description='CPU at 98%'" \
  -e "target_host=app-server-01"
```

**Skip Git push (local only):**
```bash
ansible-playbook generate-and-push.yml --skip-tags git
```

### MCP-Based Job Template Matching

**Find matching job templates for an event:**
```bash
ansible-playbook playbooks/find-matching-job-template.yml \
  -e "event_type=disk_alert" \
  -e "event_service=nginx" \
  -e "event_hostname=web-server-01" \
  -e "event_severity=high" \
  -e 'event_tags=["web","production"]'
```

**Test the integration:**
```bash
./test-mcp-integration.sh
```

### Event-Driven Automation (EDA)

**Run EDA rulebook:**
```bash
ansible-rulebook \
  --rulebook rulebooks/find-template-on-unmatched-event.yml \
  --inventory inventory.yml \
  --verbose
```

**Send test event via webhook:**
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
      "tags": ["web", "production"]
    }
  }'
```

## Architecture

### Code Assistant Playbook Generation
1. Receives event details (type, description, target)
2. Calls Red Hat Code Assistant API for AI-generated playbook
3. Saves playbook to `generated-playbooks/playbooks/`
4. Commits and pushes to Git repository

### MCP Job Template Matching
1. Receives event from EDA or direct invocation
2. Queries AAP via MCP server for available job templates
3. Matches templates against event attributes (type, service, hostname, severity, tags)
4. Scores and ranks templates by relevance
5. Returns top recommendations or auto-launches best match

### Event-Driven Flow
```
Event Source → EDA Rulebook → Specific Rules Match?
                                    ├── Yes → Run Job Template
                                    └── No  → Find Match via MCP
                                              ├── High Score → Auto-launch
                                              └── Low Score → Show recommendations
```

## Output

Generated playbooks are saved in:
```
generated-playbooks/
└── playbooks/
    ├── disk_full_web-server-01_example_com.yml
    ├── high_cpu_app-server-03_prod_example_com.yml
    └── ...
```

## Requirements

### Services
- **Red Hat Automation Code Assistant**: AI playbook generation (built into AAP 2.6+ Lightspeed) - Required for unknown event handling
- **[AAP MCP Server](https://github.com/ansible/aap-mcp-server)**: Model Context Protocol server for AAP (http://localhost:3000/mcp)
- **Ansible Automation Platform**: Version 2.6+ with MCP and Lightspeed support

### Tools
- Ansible Core 2.16+
- Python 3.10+
- Git
- ansible-rulebook (for EDA)

### Credentials
- GitHub/GitLab Personal Access Token (for Git push)
- AAP Bearer Token (for MCP authentication)

## Examples

### Maya Playbook Generation

**Disk full event:**
```bash
ansible-playbook generate-and-push.yml \
  -e "event_type=disk_full" \
  -e "event_description='Disk at 95% on /var/log'" \
  -e "target_host=web01.example.com"
```

**Service down:**
```bash
ansible-playbook generate-and-push.yml \
  -e "event_type=service_down" \
  -e "event_description='Nginx service stopped'" \
  -e "target_host=lb01.example.com"
```

**High CPU:**
```bash
ansible-playbook generate-and-push.yml \
  -e "event_type=high_cpu" \
  -e "event_description='CPU usage at 98%'" \
  -e "target_host=app-server-01"
```

### MCP Template Matching

**Database performance issue:**
```bash
ansible-playbook playbooks/find-matching-job-template.yml \
  -e "event_type=database_slow" \
  -e "event_service=postgresql" \
  -e "event_hostname=db-primary-01" \
  -e "event_severity=critical" \
  -e 'event_tags=["database","production","performance"]'
```

**Security alert:**
```bash
ansible-playbook playbooks/find-matching-job-template.yml \
  -e "event_type=security_breach" \
  -e "event_service=firewall" \
  -e "event_hostname=fw-01" \
  -e "event_severity=critical" \
  -e 'event_tags=["security","network","intrusion"]'
```

## Documentation

### Internal Documentation
- **[Quick Start Guide](QUICKSTART.md)** - Get started in 5 minutes
- **[EDA MCP Integration Guide](docs/EDA-MCP-INTEGRATION.md)** - Comprehensive guide for MCP integration
- **[AAP Job Templates Setup](AAP-JOB-TEMPLATES-SETUP.md)** - Configure AAP job templates
- **[Deployment Guide](DEPLOYMENT-GUIDE.md)** - Production deployment guide
- **[Architecture](docs/ARCHITECTURE.md)** - System architecture and design
- **[Scoring Algorithm](docs/SCORING-ALGORITHM.md)** - Template matching algorithm details

### Related Projects
- **Red Hat Automation Code Assistant** - AI-powered playbook generator (built into AAP 2.6+)
- **[Ansible MCP Collection](https://github.com/ansible-collections/ansible.mcp)** - MCP client for Ansible
- **[AAP MCP Server](https://github.com/ansible/aap-mcp-server)** - MCP server for AAP

## Project Structure

```
ansible-aiops/
├── playbooks/
│   └── find-matching-job-template.yml    # MCP-based template finder
├── rulebooks/
│   └── find-template-on-unmatched-event.yml  # EDA rulebook
├── generated-playbooks/
│   └── playbooks/                        # AI-generated playbooks
├── docs/
│   └── EDA-MCP-INTEGRATION.md           # Integration guide
├── requirements.yml                      # Ansible collection requirements
├── generate-and-push.yml                # Maya playbook generator
├── test-mcp-integration.sh              # Test script
└── .env.example                         # Environment template
```

## Contributing

Contributions welcome! Areas of interest:
- Enhanced scoring algorithms for template matching
- Additional EDA event sources
- Custom MCP tools for AAP
- Integration with other monitoring systems

## License

See LICENSE file for details.
