# Testing with curl - Sample Events

Use these curl commands to send test events to the EDA Event Stream endpoint.

All sample event payloads are in the `tests/` directory.

## Setup

Set your EDA Event Stream URL and Basic Auth credentials before running:

```bash
export EDA_EVENT_STREAM_URL="https://aapaio.lab.gineesh.com:443/eda-event-streams/api/eda/v1/external_event_stream/09df4aa9-05ff-4bbd-976e-b5278d314c78/post/"
export EDA_BASIC_AUTH="edatest:123456789"
```

> **Note:** In AAP 2.7, events must go through the gateway via an Event Stream (HTTPS).
> Direct webhook access on port 5000 is not supported.

## Using Test Scripts

Each test has a wrapper script that handles the curl call:

```bash
# Run a single test
./tests/0-debug.sh

# Run all tests sequentially (pauses between each)
./tests/run-all-tests.sh
```

---

## Debug Test

Prints "Hello" in EDA output. Useful to verify EDA is receiving events.

```bash
curl -sk -X POST "${EDA_EVENT_STREAM_URL}" \
  -H "Content-Type: application/json" \
  -u "${EDA_BASIC_AUTH}" \
  -d @tests/debug.json
```

## Hello AAP

Launches the "Hello World" job template in AAP.

```bash
curl -sk -X POST "${EDA_EVENT_STREAM_URL}" \
  -H "Content-Type: application/json" \
  -u "${EDA_BASIC_AUTH}" \
  -d @tests/hello-aap.json
```

---

## Case 1: Disk Usage High

Matches rulebook rule "High Disk Usage" and launches `Remediate Disk Space` job template.

```bash
curl -sk -X POST "${EDA_EVENT_STREAM_URL}" \
  -H "Content-Type: application/json" \
  -u "${EDA_BASIC_AUTH}" \
  -d @tests/case1-disk-full.json
```

**Expected:** EDA launches `Remediate Disk Space` job template on `web-server-01.example.com`.

## Case 2: Service Down

Matches rulebook rule "Service Down" and launches `Restart Service` job template.

```bash
curl -sk -X POST "${EDA_EVENT_STREAM_URL}" \
  -H "Content-Type: application/json" \
  -u "${EDA_BASIC_AUTH}" \
  -d @tests/case2-service-down.json
```

**Expected:** EDA launches `Restart Service` job template on `app-server-02.example.com`.

## Case 3: High CPU

Matches rulebook rule "High CPU Usage" and launches `Investigate High CPU` job template.

```bash
curl -sk -X POST "${EDA_EVENT_STREAM_URL}" \
  -H "Content-Type: application/json" \
  -u "${EDA_BASIC_AUTH}" \
  -d @tests/case3-high-cpu.json
```

**Expected:** EDA launches `Investigate High CPU` job template on `db-server-01.example.com`.

## Case 4: Certificate Expiry

Matches rulebook rule "Certificate Expiry Warning" and launches `Renew SSL Certificate` job template.

```bash
curl -sk -X POST "${EDA_EVENT_STREAM_URL}" \
  -H "Content-Type: application/json" \
  -u "${EDA_BASIC_AUTH}" \
  -d @tests/case4-cert-expiry.json
```

**Expected:** EDA launches `Renew SSL Certificate` job template on `lb-01.example.com`.

## Case 5: Unknown Event (AI Intelligence)

No match in Cases 1-4. Falls through to the default rule and launches `AI Intelligence - Unknown Event Remediation` job template.

```bash
curl -sk -X POST "${EDA_EVENT_STREAM_URL}" \
  -H "Content-Type: application/json" \
  -u "${EDA_BASIC_AUTH}" \
  -d @tests/case-unknown-event.json
```

**Expected:** EDA launches `AI Intelligence - Unknown Event Remediation` which runs MCP search, AI playbook generation, and Git push.

---

## Elastic-Style Events

Simulated payloads matching what Elastic SIEM or Watcher would send via webhook.

### Elastic SIEM Alert

```bash
curl -sk -X POST "${EDA_EVENT_STREAM_URL}" \
  -H "Content-Type: application/json" \
  -u "${EDA_BASIC_AUTH}" \
  -d @tests/elastic-siem-alert.json
```

### Elasticsearch Watcher Alert

```bash
curl -sk -X POST "${EDA_EVENT_STREAM_URL}" \
  -H "Content-Type: application/json" \
  -u "${EDA_BASIC_AUTH}" \
  -d @tests/elastic-watcher-alert.json
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
