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
                                               ┌────────────┴────────────┐
                                               │                        │
                                          Primary Path            Fallback Path
                                          (Query via MCP)    (Direct AAP REST API)
                                               │              mcp_api_fallback=true
                                               │              query_api.yml
                                               ▼                        │
                                ┌───────────────────────────┐           │
                                │  AAP MCP Server           │           │
                                │  (Port 3000/8448)         │           │
                                │                           │           │
                                │  • OAuth2 Authentication  │           │
                                │  • OpenAPI-based Tools    │           │
                                │  • RBAC Enforcement       │           │
                                │  • Read/Write Mode Control│           │
                                └─────────────┬─────────────┘           │
                                              │                         │
                                              │ REST API                │
                                              ▼                         │
                                ┌──────────────────────────────────┐    │
                                │  Ansible Automation Platform     │◀───┘
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

### 3. Template Discovery (MCP Integration with API Fallback)

```
┌────────────────────────────────────────────────────────────┐
│  internal.aiops.aiops_mcp_matcher role                      │
├────────────────────────────────────────────────────────────┤
│  Step 1: Retrieve Job Templates                            │
│                                                             │
│    ┌─ Primary: MCP Server (via connection plugin)          │
│    │   ansible.mcp.run_tool:                               │
│    │     name: job_templates_list                          │
│    │     delegate_to: aap_mcp (ansible.mcp.mcp connection)│
│    │     → Returns: All accessible job templates           │
│    │                                                       │
│    └─ Fallback: Direct AAP REST API (query_api.yml)       │
│        When: MCP skipped, not configured, or query fails   │
│        Flag: mcp_api_fallback (default true)               │
│        GET /api/controller/v2/job_templates/                          │
│        Authorization: Bearer <token>                       │
│        → Returns: Same template data via REST              │
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

### Successful Auto-Launch Path (via MCP)

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

### Successful Auto-Launch Path (API Fallback)

When MCP is skipped, not configured, or fails, the matcher queries AAP directly:

```
┌─────────┐     ┌─────────┐     ┌──────────┐     ┌──────────────┐     ┌─────────┐
│ Event   │────▶│   EDA   │────▶│Template  │────▶│ AAP REST API │────▶│   AAP   │
│ Webhook │     │Rulebook │     │  Finder  │     │ /api/v2/     │     │Launch   │
└─────────┘     └─────────┘     └──────────┘     │ job_templates│     └─────────┘
    1.              2.               3.           └──────────────┘         5.
  Receive         No rule       MCP unavail-          4.              Launch
   event          matches       able; fall         Direct REST       Job #42
                                back to API        query with        (Score:130)
                                (query_api.yml)    bearer token
```

Flag: `mcp_api_fallback` (default `true`). Task file: `query_api.yml`.

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

### Request Flow (Primary: MCP)

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
                        │ /api/controller/v2/job_templates/
                        │
                        ▼
┌──────────────────────────────────────────────────────────────┐
│  Ansible Automation Platform                                 │
│  • Query job templates                                       │
│  • Apply user RBAC                                           │
│  • Return filtered results                                   │
└──────────────────────────────────────────────────────────────┘
```

### Request Flow (Fallback: Direct AAP REST API)

When MCP is skipped (`skip_mcp=true`), not configured, or the MCP query fails,
the `aiops_mcp_matcher` role falls back to querying the AAP Controller REST API
directly. Controlled by `mcp_api_fallback` (default `true`). Task file: `query_api.yml`.

```
┌──────────────────────────────────────────────────────────────┐
│  Ansible Playbook (ansible.builtin.uri)                      │
└───────────────────────┬──────────────────────────────────────┘
                        │
                        │ HTTP GET
                        │ Authorization: Bearer <token>
                        │ GET /api/controller/v2/job_templates/
                        │
                        ▼
┌──────────────────────────────────────────────────────────────┐
│  Ansible Automation Platform (Controller API)                │
│                                                               │
│  1. Validate Bearer Token                                    │
│  2. Apply RBAC Permissions                                   │
│  3. Return Job Templates                                     │
└──────────────────────────────────────────────────────────────┘
```

The fallback produces the same template data structure as the MCP path, so
downstream scoring (LLM or Jinja) works identically regardless of which
discovery method was used.

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
│  │  ansible-rulebook (Event Stream/HTTPS)   │ │
│  └───────────┬──────────────────────────────┘ │
│              │                                 │
│  ┌───────────▼──────────────────────────────┐ │
│  │  Playbooks (ansible.mcp)                 │ │
│  └───────────┬──────────────────────────────┘ │
│              │                                 │
│  ┌───────────▼──────────────────────────────┐ │
│  │  AAP MCP Server (aap:8448)               │ │
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
│    • CLI (ansible-navigator, ansible-rulebook)          │
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
┌──────────────────────────────────────────────────────┐
│  intelligent-aiops-workflow.yml                       │
│                                                       │
│  1. Query for Templates                               │
│     ├─ Primary: MCP Server (ansible.mcp.run_tool)    │
│     └─ Fallback: AAP REST API (query_api.yml)        │
│        (when MCP skipped/unavailable/fails;           │
│         flag: mcp_api_fallback, default true)         │
│                                                       │
│  2. If Score < Threshold:                             │
│     ├─ Build structured prompt                        │
│     ├─ Call Code Assistant API                        │
│     ├─ Validate generated playbook                    │
│     └─ Push to Git review branch                      │
│                                                       │
│  3. Optional AI Review Pass                           │
│     (flag: ai_review_enabled, default false)          │
│     ├─ Second AI pass reviews generated playbook      │
│     └─ Pushes improved version to <branch>_review     │
│                                                       │
│  4. CaC Resource Creation (deferred by default)       │
│     (flag: cac_after_code_review, default true)       │
│     ├─ When true: CaC skipped in main workflow        │
│     │   → Use standalone playbooks/cac-create-jt.yml  │
│     │     after code review is complete                │
│     └─ When false: CaC runs inline (legacy behavior)  │
│        (flag: cac_create_workflow, default true)       │
│        ├─ true: Creates JT + Approval WF              │
│        └─ false: JT-only mode (no WF)                 │
└──────────────────────────────────────────────────────┘
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
│  Branch: aiops/<event_type>-<HHMMSS>   │
└──────────────────┬─────────────────────┘
                   │
        ┌──────────┴──────────┐
        │ ai_review_enabled?  │
        └──────────┬──────────┘
           false   │   true
        ┌──────────┤──────────┐
        │          │          ▼
        │          │  ┌──────────────────────────────┐
        │          │  │  AI Review Pass               │
        │          │  │  • Reviews generated playbook  │
        │          │  │  • Pushes improved version     │
        │          │  │  • Branch: <branch>_review     │
        │          │  └──────────┬───────────────────┘
        │          │             │
        └──────────┴─────────────┘
                   │
        ┌──────────┴──────────────┐
        │ cac_after_code_review?  │
        └──────────┬──────────────┘
           true    │    false
        ┌──────────┤──────────────┐
        │          │              ▼
        ▼          │  ┌──────────────────────────────┐
  ┌───────────┐    │  │  CaC Inline (legacy)         │
  │ Deferred  │    │  │  aiops_cac_manager role       │
  │ (default) │    │  │  • Creates Project, JT, WF    │
  │ Run later │    │  │  • Auto-launches WF            │
  │ via cac-  │    │  └──────────────────────────────┘
  │ create-   │    │
  │ jt.yml    │    │
  └───────────┘    │
                   ▼
              (Workflow Complete)
```

**API Endpoint:**
```yaml
lightspeed_url: "http://lightspeed-coding-assistant:8000/api/v0/ai/generations/"
```

**See:** [AAP 2.6 Lightspeed Documentation](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6) for deployment and configuration.

### Deferred CaC Workflow

When `cac_after_code_review=true` (default), the main workflow skips CaC resource
creation. After a human reviews the generated playbook on the review branch, run
the standalone playbook to create AAP resources:

```
┌──────────────────┐     ┌──────────────┐     ┌──────────────────────────┐
│  Code Review     │────▶│  Operator    │────▶│  cac-create-jt.yml       │
│  (Git PR/MR)     │     │  Approval    │     │  Creates JT (+ optional  │
└──────────────────┘     └──────────────┘     │  WF if cac_create_work-  │
                                               │  flow=true)              │
                                               └──────────────────────────┘
```

The `cac_create_workflow` flag (default `true`) in the `aiops_cac_manager` role
controls whether a workflow template with an approval node is created alongside
the job template. Set to `false` for JT-only mode when external approval
processes (Git PR reviews, change management) are already in place.
