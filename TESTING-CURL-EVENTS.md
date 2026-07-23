# Testing with curl - Sample Events

Use these curl commands to send test events to the EDA webhook endpoint.

Replace `localhost:5000` with your EDA controller webhook URL (e.g., `https://your-eda-controller:5000`).

---

## Debug Test

Prints "Hello" in EDA output. Useful to verify EDA is receiving events.

```bash
curl -X POST http://localhost:5000/webhook \
  -H "Content-Type: application/json" \
  -d '{"debug": true}'
```

## Hello AAP

Launches the "Hello World" job template in AAP.

```bash
curl -X POST http://localhost:5000/webhook \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello AAP"}'
```

With additional event details:

```bash
curl -X POST http://localhost:5000/webhook \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello AAP", "source": "prometheus", "host": "web-01", "severity": "info"}'
```

---

## Case 1: Disk Usage High

Matches rulebook rule "High Disk Usage" and launches `Remediate Disk Space` job template.

```bash
curl -X POST http://localhost:5000/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "alert_name": "disk_usage_high",
    "host": "web-server-01",
    "severity": "high",
    "partition": "/var",
    "value": 95
  }'
```

**Expected:** EDA launches `Remediate Disk Space` job template on `web-server-01`.

## Case 2: Service Down

Matches rulebook rule "Service Down" and launches `Restart Service` job template.

```bash
curl -X POST http://localhost:5000/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "alert_name": "service_down",
    "host": "app-server-01",
    "severity": "critical",
    "service": "httpd",
    "state": "down"
  }'
```

**Expected:** EDA launches `Restart Service` job template on `app-server-01`.

## Case 3: High CPU

Matches rulebook rule "High CPU Usage" and launches `Investigate High CPU` job template.

```bash
curl -X POST http://localhost:5000/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "alert_name": "high_cpu",
    "host": "db-server-01",
    "severity": "warning",
    "metric": "cpu",
    "value": 92,
    "duration_minutes": 15
  }'
```

**Expected:** EDA launches `Investigate High CPU` job template on `db-server-01`.

## Case 4: Certificate Expiry

Matches rulebook rule "Certificate Expiry Warning" and launches `Renew SSL Certificate` job template.

```bash
curl -X POST http://localhost:5000/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "alert_name": "certificate_expiry",
    "host": "lb-01.example.com",
    "severity": "high",
    "cert_path": "/etc/ssl/certs/server.crt",
    "days_until_expiry": 7
  }'
```

**Expected:** EDA launches `Renew SSL Certificate` job template on `lb-01.example.com`.

## Case 5: Unknown Event (AI Intelligence)

No match in Cases 1-4. Falls through to the default rule and launches `AI Intelligence - Unknown Event Remediation` job template.

```bash
curl -X POST http://localhost:5000/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "event_type": "database_slow_query",
    "host": "db-server-03",
    "severity": "medium",
    "service": "postgresql",
    "description": "Queries taking >5 seconds"
  }'
```

**Expected:** EDA launches `AI Intelligence - Unknown Event Remediation` which runs MCP search, AI playbook generation, and Git push.

---

## Elastic-Style Events

Simulated payloads matching what Elastic SIEM or Watcher would send via webhook.

### Elastic SIEM Alert

```bash
curl -X POST http://localhost:5000/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "rule_name": "High CPU Usage Detected",
    "severity": "high",
    "risk_score": 75,
    "description": "CPU usage exceeded 90% for 5 minutes",
    "host": {
      "name": "web-server-01",
      "ip": "192.168.1.100"
    },
    "event": {
      "kind": "signal",
      "category": ["process"],
      "action": "high_cpu"
    },
    "source": "elastic-siem",
    "tags": ["cpu", "performance", "production"],
    "timestamp": "2026-07-23T10:30:45.123Z"
  }'
```

### Elasticsearch Watcher Alert

```bash
curl -X POST http://localhost:5000/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "watch_id": "disk_usage_watch",
    "alert_name": "disk_usage_high",
    "host": "db-server-01",
    "severity": "critical",
    "metric": "disk",
    "value": 95,
    "partition": "/var",
    "service": "postgresql",
    "tags": ["database", "storage", "production"],
    "message": "Disk usage on /var reached 95%",
    "timestamp": "2026-07-23T10:30:45.000Z"
  }'
```

---

## Verification

After sending any event, check:

1. **EDA Logs:** AAP UI → Automation Decisions → Rulebook Activations → View logs
2. **AAP Jobs:** AAP UI → Jobs → Check launched job status and output
3. **Generated Playbooks:** Check the Git repository for AI-generated playbooks (Case 5)
