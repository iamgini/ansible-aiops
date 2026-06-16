# Architecture Overview

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Event Sources                                 │
├─────────────────────────────────────────────────────────────────────┤
│  Prometheus  │  Grafana  │  Webhooks  │  Kafka  │  ServiceNow  │... │
└────────┬─────────────────────────────────────────────────────────────┘
         │
         │ Events (JSON)
         ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Ansible Event-Driven Automation                   │
│                                                                       │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │              EDA Rulebook Engine                            │    │
│  │                                                              │    │
│  │  1. Receive Event                                           │    │
│  │  2. Match Against Rules                                     │    │
│  │      ├─ Match Found → Run Specific Job Template            │    │
│  │      └─ No Match    → Run Template Finder Playbook         │    │
│  └────────────────────────────────────────────────────────────┘    │
└────────┬───────────────────────────────────────────────────┬────────┘
         │                                                    │
         │ Specific Match                                     │ No Match
         │                                                    │
         ▼                                                    ▼
┌────────────────────┐                          ┌────────────────────────┐
│  Direct Job        │                          │  Template Finder       │
│  Template Launch   │                          │  Playbook              │
└────────────────────┘                          └───────────┬────────────┘
                                                            │
                                                            │ Query via MCP
                                                            ▼
                                         ┌──────────────────────────────────┐
                                         │     AAP MCP Server (Port 3000)   │
                                         │                                  │
                                         │  • OAuth2 Authentication         │
                                         │  • OpenAPI-based Tools           │
                                         │  • RBAC Enforcement              │
                                         │  • Read/Write Mode Control       │
                                         └───────────┬──────────────────────┘
                                                     │
                                                     │ REST API
                                                     ▼
                                         ┌──────────────────────────────────┐
                                         │  Ansible Automation Platform     │
                                         │                                  │
                                         │  ┌────────────────────────────┐ │
                                         │  │  Controller                │ │
                                         │  │  • Job Templates           │ │
                                         │  │  • Inventories             │ │
                                         │  │  • Projects                │ │
                                         │  └────────────────────────────┘ │
                                         │  ┌────────────────────────────┐ │
                                         │  │  Private Automation Hub    │ │
                                         │  │  • Collections             │ │
                                         │  └────────────────────────────┘ │
                                         │  ┌────────────────────────────┐ │
                                         │  │  EDA Controller            │ │
                                         │  │  • Rulebooks               │ │
                                         │  │  • Activations             │ │
                                         │  └────────────────────────────┘ │
                                         └──────────────────────────────────┘
```

## Component Interaction Flow

### 1. Event Ingestion

```
Monitoring System → EDA Webhook/Kafka/Source → EDA Rulebook
```

**Event Schema:**
```json
{
  "type": "disk_alert",
  "source": "prometheus",
  "payload": {
    "hostname": "web-server-01",
    "service": "nginx",
    "severity": "high",
    "usage": 95,
    "tags": ["web", "production"],
    "timestamp": "2026-06-04T00:00:00Z"
  }
}
```

### 2. Rule Matching (EDA Rulebook)

```
┌─────────────────────────────────────┐
│  EDA Rule Evaluation                │
├─────────────────────────────────────┤
│  1. Check Condition                 │
│     if event.severity == "critical" │
│        AND                           │
│        event.environment == "prod"  │
│                                      │
│  2. Action                           │
│     ├─ Match: Launch template #42   │
│     └─ No Match: Find template      │
└─────────────────────────────────────┘
```

### 3. Template Discovery (MCP Integration)

```
┌────────────────────────────────────────────────────────────┐
│  find-matching-job-template.yml                            │
├────────────────────────────────────────────────────────────┤
│  Step 1: Query MCP Server                                  │
│    ansible.mcp.run_tool:                                   │
│      tool_name: controller_api_v2_job_templates_list       │
│      → Returns: All accessible job templates               │
│                                                             │
│  Step 2: Filter & Match                                    │
│    • Event type in template name                           │
│    • Service name in template name/description             │
│    • Hostname matches                                      │
│    • Tags match                                            │
│    → Matched templates: 15                                 │
│                                                             │
│  Step 3: Score & Rank                                      │
│    Template A: 130 points (excellent)                      │
│    Template B: 90 points (very good)                       │
│    Template C: 50 points (good)                            │
│    → Sorted by score descending                            │
│                                                             │
│  Step 4: Return Recommendations                            │
│    Top 5 templates OR auto-launch if score > threshold     │
└────────────────────────────────────────────────────────────┘
```

### 4. Scoring Algorithm

```
┌─────────────────────────────────────────────────────────┐
│  Scoring Matrix                                         │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  Event Type Match (name)         → +50 points           │
│  Service Name Match (name)       → +40 points           │
│  Hostname Match (name)           → +30 points           │
│  Event Type Match (description)  → +20 points           │
│  Service Name Match (description)→ +20 points           │
│  Severity Keyword Match          → +15 points           │
│  Tag Match (each)                → +10 points           │
│                                                          │
│  Total Score Range: 0 to 200+                           │
│                                                          │
│  Decision Thresholds:                                   │
│    ≥ 100: Auto-launch (if enabled)                      │
│    ≥ 80:  Top recommendation                            │
│    ≥ 50:  Show in list                                  │
│    < 50:  Weak match, use caution                       │
└─────────────────────────────────────────────────────────┘
```

## Data Flow Diagram

### Successful Auto-Launch Path

```
┌─────────┐     ┌─────────┐     ┌──────────┐     ┌─────────┐     ┌─────────┐
│ Event   │────▶│   EDA   │────▶│Template  │────▶│   MCP   │────▶│   AAP   │
│ Webhook │     │Rulebook │     │  Finder  │     │  Server │     │Launch   │
└─────────┘     └─────────┘     └──────────┘     └─────────┘     └─────────┘
    1.              2.               3.               4.              5.
  Receive         No rule       Query all        Return          Launch
   event          matches       templates        ranked          Job #42
                                                  list            (Score:130)
```

### Manual Selection Path

```
┌─────────┐     ┌─────────┐     ┌──────────┐     ┌─────────────┐
│ Event   │────▶│   EDA   │────▶│Template  │────▶│  Operator   │
│ Webhook │     │Rulebook │     │  Finder  │     │  Dashboard  │
└─────────┘     └─────────┘     └──────────┘     └─────────────┘
    1.              2.               3.                 4.
  Receive         No rule       Display Top        Operator
   event          matches       5 Templates        Selects &
                                (Scored)           Approves
                                                       │
                                                       ▼
                                                  ┌─────────┐
                                                  │   AAP   │
                                                  │ Launch  │
                                                  └─────────┘
```

## MCP Protocol Communication

### Request Flow

```
┌──────────────────────────────────────────────────────────────┐
│  Ansible Playbook (ansible.mcp collection)                   │
└───────────────────────┬──────────────────────────────────────┘
                        │
                        │ HTTP POST
                        │ Authorization: Bearer <token>
                        │ Content-Type: application/json
                        │
                        ▼
┌──────────────────────────────────────────────────────────────┐
│  AAP MCP Server (Port 3000)                                  │
│                                                               │
│  1. Validate OAuth2 Token                                    │
│  2. Check RBAC Permissions                                   │
│  3. Map to OpenAPI Tool                                      │
│  4. Execute AAP REST API Call                                │
│  5. Return Result                                            │
└───────────────────────┬──────────────────────────────────────┘
                        │
                        │ AAP REST API
                        │ /api/v2/job_templates/
                        │
                        ▼
┌──────────────────────────────────────────────────────────────┐
│  Ansible Automation Platform                                 │
│  • Query job templates                                       │
│  • Apply user RBAC                                           │
│  • Return filtered results                                   │
└──────────────────────────────────────────────────────────────┘
```

### MCP Tool Call Example

**Request:**
```json
{
  "tool": "controller_api_v2_job_templates_list",
  "arguments": {
    "page_size": 100,
    "order_by": "name"
  }
}
```

**Response:**
```json
{
  "count": 42,
  "results": [
    {
      "id": 7,
      "name": "Cleanup Disk Space - Web Servers",
      "description": "Clean up disk space on web servers",
      "project": 5,
      "inventory": 3,
      "summary_fields": {
        "project": {"name": "Infrastructure Maintenance"},
        "inventory": {"name": "Production Web Servers"}
      }
    },
    ...
  ]
}
```

## Security Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Security Layers                                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Layer 1: Authentication                                    │
│    • OAuth2 Bearer Token                                    │
│    • Token Validation via AAP                               │
│    • Token Expiration Enforcement                           │
│                                                              │
│  Layer 2: Authorization (RBAC)                              │
│    • AAP User Permissions                                   │
│    • Team-based Access Control                              │
│    • Organization Scope                                     │
│                                                              │
│  Layer 3: Operation Control                                 │
│    • Read-Only Mode (default)                               │
│    • Write Operations (explicit enable)                     │
│    • Audit Logging                                          │
│                                                              │
│  Layer 4: Network Security                                  │
│    • HTTPS/TLS for Production                               │
│    • Internal Network Only                                  │
│    • Firewall Rules                                         │
│                                                              │
│  Layer 5: Data Protection                                   │
│    • No Credential Exposure                                 │
│    • Encrypted Secrets in AAP                               │
│    • Token Rotation                                         │
└─────────────────────────────────────────────────────────────┘
```

## Deployment Architectures

### Development Environment

```
┌────────────────────────────────────────────────┐
│  Developer Laptop                              │
│  ┌──────────────────────────────────────────┐ │
│  │  ansible-rulebook (localhost:5000)       │ │
│  └───────────┬──────────────────────────────┘ │
│              │                                 │
│  ┌───────────▼──────────────────────────────┐ │
│  │  Playbooks (ansible.mcp)                 │ │
│  └───────────┬──────────────────────────────┘ │
│              │                                 │
│  ┌───────────▼──────────────────────────────┐ │
│  │  AAP MCP Server (localhost:3000)         │ │
│  └───────────┬──────────────────────────────┘ │
└──────────────┼────────────────────────────────┘
               │ HTTPS
               ▼
       ┌───────────────┐
       │  AAP SaaS or  │
       │  Remote AAP   │
       └───────────────┘
```

### Production Environment

```
┌─────────────────────────────────────────────────────────────┐
│  Kubernetes/OpenShift Cluster                               │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  EDA Controller (Managed Service)                      │ │
│  │  • Runs EDA Rulebooks                                  │ │
│  │  • Receives Events from Multiple Sources               │ │
│  └───────────┬────────────────────────────────────────────┘ │
│              │                                               │
│  ┌───────────▼────────────────────────────────────────────┐ │
│  │  AAP MCP Server (HA Deployment)                        │ │
│  │  • Load Balanced                                       │ │
│  │  • Auto-scaling                                        │ │
│  │  • Internal Service                                    │ │
│  └───────────┬────────────────────────────────────────────┘ │
└──────────────┼──────────────────────────────────────────────┘
               │
               │ Private Network
               ▼
       ┌───────────────────────┐
       │  AAP Controller       │
       │  (On-Prem/Cloud)      │
       │  • Job Templates      │
       │  • Inventories        │
       │  • Credentials        │
       └───────────────────────┘
```

## Scalability Considerations

### Horizontal Scaling

```
                    ┌─────────────┐
                    │Load Balancer│
                    └──────┬──────┘
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
    ┌────▼────┐       ┌────▼────┐      ┌────▼────┐
    │ MCP     │       │ MCP     │      │ MCP     │
    │ Server  │       │ Server  │      │ Server  │
    │ Pod 1   │       │ Pod 2   │      │ Pod 3   │
    └────┬────┘       └────┬────┘      └────┬────┘
         │                 │                 │
         └─────────────────┼─────────────────┘
                           │
                      ┌────▼────┐
                      │   AAP   │
                      │Controller│
                      └─────────┘
```

### Caching Strategy

```
┌──────────────────────────────────────────┐
│  MCP Server with Cache                   │
│  ┌────────────────────────────────────┐ │
│  │  Template Metadata Cache           │ │
│  │  • TTL: 5 minutes                  │ │
│  │  • Invalidate on Write             │ │
│  │  • LRU Eviction                    │ │
│  └────────────────────────────────────┘ │
│  ┌────────────────────────────────────┐ │
│  │  Token Validation Cache            │ │
│  │  • TTL: 1 minute                   │ │
│  │  • Per-token basis                 │ │
│  └────────────────────────────────────┘ │
└──────────────────────────────────────────┘
```

## Monitoring & Observability

### Metrics to Track

```
┌─────────────────────────────────────────────┐
│  Metrics Dashboard                          │
├─────────────────────────────────────────────┤
│  • Events received per minute              │
│  • Rule matches vs. MCP queries            │
│  • MCP query latency                       │
│  • Template match scores (avg/distribution)│
│  • Auto-launch success rate                │
│  • Job execution outcomes                  │
│  • Token validation failures               │
│  • API rate limits                         │
└─────────────────────────────────────────────┘
```

### Logging Flow

```
┌─────────┐     ┌─────────┐     ┌─────────┐     ┌──────────┐
│   EDA   │────▶│Template │────▶│   MCP   │────▶│   AAP    │
│  Logs   │     │ Finder  │     │  Logs   │     │   Logs   │
└────┬────┘     └────┬────┘     └────┬────┘     └────┬─────┘
     │               │               │               │
     └───────────────┴───────────────┴───────────────┘
                     │
                     ▼
            ┌────────────────┐
            │  Log Aggregator│
            │ (ELK/Splunk)   │
            └────────────────┘
```

## Integration Points

### External System Integration

```
┌─────────────────┐
│  Prometheus     │─┐
└─────────────────┘ │
┌─────────────────┐ │
│  Grafana        │─┤
└─────────────────┘ │
┌─────────────────┐ │    ┌──────────┐     ┌─────────┐
│  ServiceNow     │─┼───▶│   EDA    │────▶│   MCP   │
└─────────────────┘ │    │ Rulebook │     │Template │
┌─────────────────┐ │    └──────────┘     │ Finder  │
│  PagerDuty      │─┤                      └─────────┘
└─────────────────┘ │
┌─────────────────┐ │
│  Custom Webhooks│─┘
└─────────────────┘
```

## Technology Stack

```
┌─────────────────────────────────────────────────────────┐
│  Technology Components                                  │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  Frontend/Interface:                                    │
│    • AAP Web UI                                         │
│    • EDA Dashboard                                      │
│    • CLI (ansible-playbook, ansible-rulebook)          │
│                                                          │
│  Automation Layer:                                      │
│    • Ansible Core 2.16+                                 │
│    • ansible-rulebook                                   │
│    • ansible.mcp collection                             │
│    • ansible.eda collection                             │
│                                                          │
│  Integration Layer:                                     │
│    • AAP MCP Server (Node.js/Python)                    │
│    • OpenAPI Specifications                             │
│    • Model Context Protocol                             │
│                                                          │
│  Platform:                                              │
│    • Red Hat Ansible Automation Platform 2.6.4+         │
│    • AAP Controller                                     │
│    • Private Automation Hub                             │
│    • EDA Controller                                     │
│                                                          │
│  Infrastructure:                                        │
│    • Container Runtime (Podman/Docker)                  │
│    • Kubernetes/OpenShift (Production)                  │
│    • PostgreSQL (AAP Database)                          │
│    • Redis (Caching, optional)                          │
│                                                          │
│  AI/LLM Layer (Optional - for Unknown Events):         │
│    • Red Hat Automation Code Assistant (Lightspeed)     │
│      Built into AAP 2.6+ for AI playbook generation     │
│    • LLM Provider (Claude/OpenAI/Ollama)                │
└─────────────────────────────────────────────────────────┘
```

## Integration with Red Hat Automation Code Assistant

For unknown events that don't match any existing job templates, this project integrates with **Red Hat Automation Code Assistant** (Lightspeed, built into AAP 2.6+) for AI-powered playbook generation.

This follows the **AIOps multi-LLM workflow pattern** where:
- **Red Hat AI** (optional) analyzes and diagnoses incidents
- **Code Assistant** generates remediation playbooks

Reference: [Ansible AIOps Solution Guide](https://ansible-tmm.github.io/solution-guides/README-AIOps.html)

### Code Assistant Integration Flow

```
┌──────────────┐
│ Unknown Event│
│  (No Match)  │
└──────┬───────┘
       │
       ▼
┌────────────────────────────────────────┐
│  intelligent-aiops-workflow.yml        │
│                                        │
│  1. Query MCP for Templates            │
│  2. If Score < Threshold:              │
│     ├─ Build structured prompt         │
│     ├─ Call Code Assistant API         │
│     ├─ Validate generated playbook     │
│     └─ Push to Git Repository          │
└────────────────────────────────────────┘
       │
       ▼
┌────────────────────────────────────────┐
│  Red Hat Code Assistant (Lightspeed)   │
│  (AI Playbook Generator - AAP 2.6+)    │
│                                        │
│  • Prompt Analysis                     │
│  • LLM-Based Generation                │
│  • FQCN Best Practices                 │
│  • Ansible-Specific Training           │
│  • Enterprise AI Models                │
└────────────────────────────────────────┘
       │
       ▼
┌────────────────────────────────────────┐
│  Generated Playbook                    │
│  (Validated & Committed to Git)        │
└────────────────────────────────────────┘
```

**API Endpoint:**
```yaml
lightspeed_url: "http://lightspeed-coding-assistant:8000/api/v0/ai/generations/"
```

**See:** [AAP 2.6 Lightspeed Documentation](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6) for deployment and configuration.
