# Playbook Cleanup Analysis

## Current Playbooks

### ❌ REMOVE: `execute-aap-job-template.yml`
**Why:** No longer needed - the rulebook now uses `run_job_template` action directly instead of calling this playbook.

**Old approach (via playbook):**
```yaml
# Rulebook called playbook, playbook launched AAP job
action:
  run_playbook:
    name: playbooks/execute-aap-job-template.yml
```

**New approach (direct):**
```yaml
# Rulebook launches AAP job directly
action:
  run_job_template:
    name: "Remediate Disk Space"
```

### ⚠️ ARCHIVE: `find-matching-job-template.yml`
**Why:** Only used by old rulebook. The new `intelligent-aiops-workflow.yml` does MCP search inline.

**Decision:** Archive (not delete) - might be useful standalone

### ✅ KEEP: `intelligent-aiops-workflow.yml`
**Why:** Used by Case 5 (unknown events) in the new rulebook. This is the core AI intelligence workflow.

**Status:** Production-ready, actively used

## What We Need to Create

**4 Remediation Playbooks for AAP:**

1. `remediation/disk-cleanup.yml` - Case 1: Disk cleanup
2. `remediation/restart-service.yml` - Case 2: Service restart
3. `remediation/investigate-cpu.yml` - Case 3: CPU investigation
4. `remediation/renew-certificate.yml` - Case 4: Certificate renewal

These will run **IN AAP** on target hosts, not on EDA controller.

## Final Structure

```
playbooks/
├── remediation/                              ← NEW: AAP remediation playbooks
│   ├── disk-cleanup.yml                     ✅ Create
│   ├── restart-service.yml                  ✅ Create
│   ├── investigate-cpu.yml                  ✅ Create
│   └── renew-certificate.yml                ✅ Create
├── intelligent-aiops-workflow.yml           ✅ Keep (Case 5)
└── generate-and-push.yml                    ✅ Keep (standalone tool)

archive/old-playbooks/                        📦 Archived
├── execute-aap-job-template.yml             ❌ Removed
└── find-matching-job-template.yml           ⚠️ Archived
```
