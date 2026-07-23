# Testing with curl - Sample Events

Use these curl commands to send test events to the EDA webhook endpoint.

All sample event payloads are in the `test-events/` directory.

## Setup

Set your EDA webhook URL before running the commands:

```bash
export EDA_WEBHOOK_URL=https://localhost:5000
```

---

## Debug Test

Prints "Hello" in EDA output. Useful to verify EDA is receiving events.

```bash
curl -X POST ${EDA_WEBHOOK_URL}/webhook \
  -H "Content-Type: application/json" \
  -d @test-events/debug.json
```

## Hello AAP

Launches the "Hello World" job template in AAP.

```bash
curl -X POST ${EDA_WEBHOOK_URL}/webhook \
  -H "Content-Type: application/json" \
  -d @test-events/hello-aap.json
```

---

## Case 1: Disk Usage High

Matches rulebook rule "High Disk Usage" and launches `Remediate Disk Space` job template.

```bash
curl -X POST ${EDA_WEBHOOK_URL}/webhook \
  -H "Content-Type: application/json" \
  -d @test-events/case1-disk-full.json
```

**Expected:** EDA launches `Remediate Disk Space` job template on `web-server-01.example.com`.

## Case 2: Service Down

Matches rulebook rule "Service Down" and launches `Restart Service` job template.

```bash
curl -X POST ${EDA_WEBHOOK_URL}/webhook \
  -H "Content-Type: application/json" \
  -d @test-events/case2-service-down.json
```

**Expected:** EDA launches `Restart Service` job template on `app-server-02.example.com`.

## Case 3: High CPU

Matches rulebook rule "High CPU Usage" and launches `Investigate High CPU` job template.

```bash
curl -X POST ${EDA_WEBHOOK_URL}/webhook \
  -H "Content-Type: application/json" \
  -d @test-events/case3-high-cpu.json
```

**Expected:** EDA launches `Investigate High CPU` job template on `db-server-01.example.com`.

## Case 4: Certificate Expiry

Matches rulebook rule "Certificate Expiry Warning" and launches `Renew SSL Certificate` job template.

```bash
curl -X POST ${EDA_WEBHOOK_URL}/webhook \
  -H "Content-Type: application/json" \
  -d @test-events/case4-cert-expiry.json
```

**Expected:** EDA launches `Renew SSL Certificate` job template on `lb-01.example.com`.

## Case 5: Unknown Event (AI Intelligence)

No match in Cases 1-4. Falls through to the default rule and launches `AI Intelligence - Unknown Event Remediation` job template.

```bash
curl -X POST ${EDA_WEBHOOK_URL}/webhook \
  -H "Content-Type: application/json" \
  -d @test-events/case-unknown-event.json
```

**Expected:** EDA launches `AI Intelligence - Unknown Event Remediation` which runs MCP search, AI playbook generation, and Git push.

---

## Elastic-Style Events

Simulated payloads matching what Elastic SIEM or Watcher would send via webhook.

### Elastic SIEM Alert

```bash
curl -X POST ${EDA_WEBHOOK_URL}/webhook \
  -H "Content-Type: application/json" \
  -d @test-events/elastic-siem-alert.json
```

### Elasticsearch Watcher Alert

```bash
curl -X POST ${EDA_WEBHOOK_URL}/webhook \
  -H "Content-Type: application/json" \
  -d @test-events/elastic-watcher-alert.json
```

---

## Test Events Summary

| File | Rulebook Match | Job Template |
|------|---------------|--------------|
| `debug.json` | Debug Hello | (prints "Hello" in EDA) |
| `hello-aap.json` | Hello AAP | Hello World |
| `case1-disk-full.json` | High Disk Usage | Remediate Disk Space |
| `case2-service-down.json` | Service Down | Restart Service |
| `case3-high-cpu.json` | High CPU Usage | Investigate High CPU |
| `case4-cert-expiry.json` | Certificate Expiry | Renew SSL Certificate |
| `case-unknown-event.json` | Default (Case 5) | AI Intelligence - Unknown Event Remediation |
| `elastic-siem-alert.json` | Default (Case 5) | AI Intelligence - Unknown Event Remediation |
| `elastic-watcher-alert.json` | High Disk Usage | Remediate Disk Space |

## Verification

After sending any event, check:

1. **EDA Logs:** AAP UI → Automation Decisions → Rulebook Activations → View logs
2. **AAP Jobs:** AAP UI → Jobs → Check launched job status and output
3. **Generated Playbooks:** Check the Git repository for AI-generated playbooks (Case 5)
