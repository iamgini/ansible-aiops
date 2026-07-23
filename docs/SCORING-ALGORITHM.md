# Job Template Matching Scoring Algorithm

## Overview

The scoring algorithm evaluates how well an AAP job template matches an incoming event. Higher scores indicate better matches, helping to automatically select the most appropriate automation response.

## Scoring Rules

| Match Type | Points | Description | Example |
|------------|--------|-------------|---------|
| **Event type in template name** | +50 | Direct match of event type in job template name | Event: `disk_alert` → Template: "Disk Alert Response" |
| **Service name in template name** | +40 | Service identifier appears in template name | Service: `nginx` → Template: "Nginx Service Recovery" |
| **Hostname in template name** | +30 | Target hostname appears in template name | Host: `web-01` → Template: "Web-01 Maintenance" |
| **Event type in description** | +20 | Event type mentioned in template description | Event: `disk_alert` → Desc: "Responds to disk alerts..." |
| **Service name in description** | +20 | Service name mentioned in template description | Service: `postgresql` → Desc: "PostgreSQL performance tuning" |
| **Severity keyword match** | +15 | Severity level matches template keywords | Severity: `critical` → Template: "Critical Incident Response" |
| **Tag match** | +10 per tag | Event tags appear in name or description | Tag: `production` → Template: "Production Service Restart" |

## Severity Keywords

The algorithm recognizes these severity-based keywords:

| Severity Level | Keywords Matched |
|----------------|------------------|
| Critical | `critical`, `emergency` |
| High | `high`, `urgent` |
| Medium | `medium`, `moderate` |
| Low | `low`, `routine` |

## Matching Logic

### 1. Template Discovery
```
Query AAP via MCP → Get all job templates → Extract metadata
```

### 2. Initial Filtering
Templates are initially matched if they contain ANY of:
- Event type in name
- Service name in name or description  
- Hostname in name
- Related tags

### 3. Scoring Phase
Each matched template receives points based on the rules above. Multiple criteria can apply to a single template, accumulating points.

### 4. Ranking
Templates are sorted by total score (descending). The top 5 are presented to the operator or the highest-scoring template can be auto-launched if score exceeds a threshold.

## Score Interpretation

| Score Range | Interpretation | Recommended Action |
|-------------|----------------|-------------------|
| **100+** | Excellent match | Auto-launch (if configured) |
| **80-99** | Very good match | Present as top recommendation |
| **50-79** | Good match | Include in recommendations |
| **25-49** | Weak match | Show but with caution |
| **< 25** | Poor match | Consider creating new template |

## Examples

### Example 1: Disk Alert on Web Server

**Event:**
```yaml
type: disk_alert
source: monitoring
payload:
  hostname: web-server-01
  service: nginx
  severity: high
  tags: [web, production, disk]
```

**Template Match:**
```yaml
name: "Cleanup Disk Space - Web Servers"
description: "Clean up disk space on web servers running nginx"
project: "Infrastructure Maintenance"
inventory: "Production Web Servers"
```

**Score Calculation:**
- Event type (`disk_alert`) in name: +50 (partial match on "Disk")
- Service (`nginx`) in description: +20
- Tag `web` in name: +10
- Tag `production` in description context: +10
- Tag `disk` in name: +10
- Severity `high` implied: +15
- **Total: 115 points** → Excellent match

### Example 2: Database Performance Issue

**Event:**
```yaml
type: database_slow
source: apm
payload:
  hostname: db-primary-01
  service: postgresql
  severity: critical
  tags: [database, production, performance]
```

**Template Match:**
```yaml
name: "PostgreSQL Performance Tuning"
description: "Tune PostgreSQL configuration for critical performance issues"
project: "Database Operations"
inventory: "Production Databases"
```

**Score Calculation:**
- Service (`postgresql`) in name: +40
- Event type (`database_slow`) partial in description: +20
- Severity (`critical`) in description: +15
- Tag `database` implied: +10
- Tag `production` context: +10
- Tag `performance` in name/description: +10
- **Total: 105 points** → Excellent match

### Example 3: Generic Service Restart

**Event:**
```yaml
type: service_down
source: uptime_monitor
payload:
  hostname: app-server-05
  service: api
  severity: medium
  tags: [api, backend]
```

**Template Match:**
```yaml
name: "Service Restart - Generic"
description: "Restart any service on any host"
project: "General Operations"
inventory: "All Servers"
```

**Score Calculation:**
- Event type (`service`) in name: +50
- Tag `backend` no match: 0
- Tag `api` no match: 0
- **Total: 50 points** → Good match (but generic)

## Customization

### Adding Custom Scoring Rules

Edit the `aiops_mcp_matcher` role (`collections/ansible_collections/internal/aiops/roles/aiops_mcp_matcher/tasks/main.yml`) and modify the scoring section:

```yaml
- name: Score templates with custom logic
  ansible.builtin.set_fact:
    scored_templates: >-
      {% set templates = [] %}
      {% for template in unique_matched_templates %}
        {% set score = 0 %}
        
        # Your custom scoring rules
        {% if 'production' in template.inventory.name | lower %}
          {% set score = score + 25 %}  # Prefer production-ready templates
        {% endif %}
        
        {% if template.last_job_run.failed == false %}
          {% set score = score + 10 %}  # Prefer templates with successful runs
        {% endif %}
        
        # ... add more rules
        
        {% set _ = templates.append({'name': template.name, 'score': score}) %}
      {% endfor %}
      {{ templates | sort(attribute='score', reverse=True) }}
```

### Weighting Strategies

Different use cases may benefit from different weighting:

**Option 1: Conservative (Favor Exact Matches)**
- Increase points for exact matches (name matches)
- Decrease points for tag/description matches
- Higher threshold for auto-launch (120+)

**Option 2: Aggressive (Favor Coverage)**
- More points for tags and descriptions
- Lower threshold for auto-launch (80+)
- Include more templates in recommendations (top 10)

**Option 3: Service-Centric**
- Double points for service name matches
- De-emphasize hostname matches
- Useful for multi-host services

**Option 4: Environment-Aware**
- Bonus points if template inventory matches event environment
- Critical events only match templates with "production" inventory
- Lower environments allow more generic matches

## Best Practices

### Template Naming Conventions
To maximize matching effectiveness:

1. **Include key entities in names:**
   - ✅ "Nginx Service Recovery - Production Web Servers"
   - ❌ "Fix-it Template #5"

2. **Use descriptive names:**
   - ✅ "Database Backup - PostgreSQL Critical Priority"
   - ❌ "DB Task"

3. **Add context in descriptions:**
   - ✅ "Responds to critical disk alerts on web servers by cleaning log files and temporary data"
   - ❌ "Cleans stuff"

4. **Tag templates appropriately in AAP:**
   - Use labels/tags in AAP that match event taxonomy
   - Common tags: environment, service type, severity level, team ownership

### Event Data Quality
Ensure events provide rich context:

```yaml
# Good event
{
  "type": "disk_alert",
  "source": "prometheus",
  "payload": {
    "hostname": "web-server-01.prod.example.com",
    "service": "nginx",
    "severity": "high",
    "usage": 95,
    "tags": ["web", "production", "disk", "nginx"],
    "environment": "production"
  }
}

# Poor event
{
  "type": "alert",
  "payload": {
    "host": "server1"
  }
}
```

## Troubleshooting

### No Matches Found
- **Check template naming:** Are templates named descriptively?
- **Verify event data:** Does the event contain searchable fields?
- **Lower threshold:** Consider showing lower-scoring matches
- **Add wildcards:** Make matching more flexible

### Too Many Low-Score Matches
- **Raise threshold:** Only show scores > 60
- **Improve template names:** Add more specific keywords
- **Use negative keywords:** Exclude templates with certain terms
- **Filter by inventory:** Only match templates with appropriate inventory

### Wrong Template Recommended
- **Adjust weights:** Tune the scoring rules
- **Add negative scoring:** Penalize certain mismatches
- **Review template descriptions:** Make them more specific
- **Add exclusion rules:** Skip templates that shouldn't auto-launch

## Future Enhancements

Potential improvements to the algorithm:

1. **Machine Learning Integration:**
   - Learn from past event→template→outcome patterns
   - Adjust weights based on success rates
   - Identify new template needs

2. **Temporal Factors:**
   - Recent successful runs get bonus points
   - Recently failed templates get penalties
   - Time-of-day relevance

3. **Dependency Awareness:**
   - Chain templates based on dependencies
   - Prefer templates that fix root causes over symptoms
   - Multi-step remediation plans

4. **Feedback Loop:**
   - Operators rate recommendations
   - Auto-adjust weights based on ratings
   - Identify gaps in template coverage

5. **Context Enrichment:**
   - Query CMDB for host/service metadata
   - Check current host state before scoring
   - Factor in ongoing incidents or maintenance windows
