# Rulebook Comparison

## Which Rulebook Should You Use?

**Use: `intelligent-remediation.yml`** ✅

This is the comprehensive rulebook that implements your complete workflow!

## Comparison

### Old: `find-template-on-unmatched-event.yml` ❌

**What it does:**
- Only MCP search for job templates
- No direct AAP launches for known events
- No Maya integration
- Incomplete workflow

**Flow:**
```
Event → Catch-all rule → MCP search → (That's it!)
```

**Problems:**
- ❌ No specific cases for known events (disk_full, service_down, etc.)
- ❌ Doesn't call Maya API
- ❌ Doesn't save generated playbooks to git
- ❌ Just finds templates but doesn't launch them

### New: `intelligent-remediation.yml` ✅

**What it does:**
- **Cases 1-4**: Known events → Direct AAP job template launch
- **Default case**: Unknown events → MCP search → Maya generation → Git push
- Complete end-to-end workflow

**Flow:**
```
Known Event (Case 1-4):
  Event → Match rule → Launch AAP job template ✅

Unknown Event (Default):
  Event → No match → MCP search
    ↓ High score? → Launch AAP job template ✅
    ↓ Low/no score? → Maya API → Generate playbook → Git push ✅
```

## Feature Comparison

| Feature | find-template-on-unmatched-event.yml | intelligent-remediation.yml |
|---------|--------------------------------------|------------------------------|
| **Specific Event Rules** | ❌ Only 2 examples | ✅ Cases 1-4 fully defined |
| **Direct AAP Launch** | ❌ Only in examples | ✅ For known events |
| **MCP Integration** | ✅ Yes | ✅ Yes (for unknown only) |
| **Maya Integration** | ❌ No | ✅ Yes (fallback) |
| **Git Push** | ❌ No | ✅ Yes |
| **Confidence Thresholds** | ❌ No | ✅ Yes (100+ = launch, <50 = Maya) |
| **Complete Workflow** | ❌ Partial | ✅ Full end-to-end |

## Workflow Details

### intelligent-remediation.yml Structure

```yaml
rules:
  # Case 1: High Disk Usage (Known)
  - condition: event.payload.alert_name == "disk_usage_high"
    action: execute-aap-job-template.yml → "Remediate Disk Space"

  # Case 2: Service Down (Known)
  - condition: event.payload.alert_name == "service_down"
    action: execute-aap-job-template.yml → "Restart Service"

  # Case 3: High CPU (Known)
  - condition: event.payload.alert_name == "high_cpu"
    action: execute-aap-job-template.yml → "Investigate High CPU"

  # Case 4: Certificate Expiry (Known)
  - condition: event.payload.alert_name == "certificate_expiry"
    action: execute-aap-job-template.yml → "Renew SSL Certificate"

  # Default: Unknown Events
  - condition: event.payload is defined  # Catches everything else
    action: intelligent-aiops-workflow.yml
      → MCP search (if score ≥100: launch AAP)
      → If score <50: Maya generate → Git push
```

## Files Structure

### With intelligent-remediation.yml (Recommended)

```
ansible-aiops/
├── rulebooks/
│   ├── intelligent-remediation.yml           ← USE THIS
│   └── find-template-on-unmatched-event.yml  ← OLD, ignore
├── playbooks/
│   ├── execute-aap-job-template.yml          ← For Cases 1-4
│   ├── intelligent-aiops-workflow.yml        ← For unknown events
│   ├── find-matching-job-template.yml        ← OLD (MCP only)
│   └── generate-and-push.yml                 ← Standalone Maya workflow
└── test-events/
    ├── case1-disk-full.json
    ├── case2-service-down.json
    ├── case3-high-cpu.json
    └── case-unknown-event.json
```

## How to Run

### Start EDA with intelligent-remediation.yml

```bash
cd ~/ansible-aiops

# Set environment variables
export AAP_MCP_SERVER_URL="http://localhost:3000/mcp"
export AAP_BEARER_TOKEN="your_aap_token"
export CONTROLLER_HOST="https://controller.example.com"
export CONTROLLER_USERNAME="admin"
export CONTROLLER_PASSWORD="password"
export GIT_TOKEN="your_github_token"
export GIT_USERNAME="iamgini"
export GIT_EMAIL="your_email@example.com"

# Start EDA rulebook
ansible-rulebook \
  --rulebook rulebooks/intelligent-remediation.yml \
  --inventory inventory.yml \
  --verbose
```

### Test Known Event (Case 1)

```bash
# Send disk_full event → Should launch "Remediate Disk Space" job template
curl -X POST http://localhost:5000/webhook \
  -H "Content-Type: application/json" \
  -d @test-events/case1-disk-full.json
```

**Expected:** Direct AAP job launch (no MCP, no Maya)

### Test Unknown Event

```bash
# Send unknown event → MCP search → Maya generation → Git push
curl -X POST http://localhost:5000/webhook \
  -H "Content-Type: application/json" \
  -d @test-events/case-unknown-event.json
```

**Expected:**
1. MCP searches for templates
2. If score < 50: Maya generates playbook
3. Playbook saved to git

## Migration Path

If you were using `find-template-on-unmatched-event.yml`:

1. **Stop using it** - It's incomplete
2. **Switch to `intelligent-remediation.yml`**
3. **Update your AAP job template names** in the rulebook (lines 22, 41, 60, 79)
4. **Test with provided test events**

## Recommendation

✅ **Use:** `intelligent-remediation.yml`  
❌ **Ignore:** `find-template-on-unmatched-event.yml`

The new rulebook gives you:
- Complete workflow (known + unknown events)
- MCP integration for intelligent matching
- Maya fallback for novel events
- Git storage for generated playbooks
- Production-ready decision logic

You can delete or archive `find-template-on-unmatched-event.yml` - it was the prototype.
