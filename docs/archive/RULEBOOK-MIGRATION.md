# Rulebook Migration Guide

## Old vs New

### ❌ OLD: `find-template-on-unmatched-event.yml` (49 lines)

**What it did:**
- Only 2 hardcoded example rules (disk_space, critical alerts)
- Catch-all rule calls `playbooks/find-matching-job-template.yml`
- Only does MCP search, no Maya integration
- No git push, no complete workflow

**Problems:**
- ❌ Incomplete - just searches MCP, doesn't do anything else
- ❌ Uses `run_playbook` - requires local execution
- ❌ No intelligent fallback to Maya
- ❌ No proper event routing
- ❌ Prototype/proof-of-concept quality

### ✅ NEW: `intelligent-remediation.yml` (120 lines)

**What it does:**
- 4 fully-defined known event rules (Cases 1-4)
- 1 intelligent unknown event rule (Case 5)
- Uses `run_job_template` - pure AAP execution
- Complete workflow: MCP → Maya → Git
- Production-ready

**Benefits:**
- ✅ Complete end-to-end workflow
- ✅ All execution in AAP (no local ansible-playbook)
- ✅ 5 distinct job templates for clear separation
- ✅ Intelligent routing with fallback
- ✅ Production-ready

## Feature Comparison

| Feature | find-template-on-unmatched-event.yml | intelligent-remediation.yml |
|---------|--------------------------------------|------------------------------|
| **Event Rules** | 2 examples only | 4 production-ready + 1 AI |
| **Action Type** | `run_playbook` (local) | `run_job_template` (AAP) |
| **Known Events** | Hardcoded examples | Cases 1-4 fully defined |
| **Unknown Events** | MCP search only | MCP → Maya → Git → AAP |
| **Execution** | Requires local setup | Pure AAP, no local needed |
| **Status** | Prototype | Production-ready |

## Migration Steps

### Step 1: Verify You're Using the New Rulebook

Check your EDA activation in AAP:

**AAP UI → Automation Decisions → Rulebook Activations**

Should point to: `rulebooks/intelligent-remediation.yml` ✅

### Step 2: Archive or Delete Old Rulebook

#### Option A: Archive (Recommended for now)

```bash
cd ~/ansible-aiops

# Create archive directory
mkdir -p archive/old-rulebooks

# Move old rulebook
mv rulebooks/find-template-on-unmatched-event.yml \
   archive/old-rulebooks/

# Add to .gitignore
echo "archive/" >> .gitignore

git add .gitignore
git commit -m "Archive old rulebook - superseded by intelligent-remediation.yml"
git push
```

#### Option B: Delete (If you're confident)

```bash
cd ~/ansible-aiops

# Delete old rulebook
rm rulebooks/find-template-on-unmatched-event.yml

git add rulebooks/
git commit -m "Remove old rulebook - superseded by intelligent-remediation.yml"
git push
```

### Step 3: Also Clean Up Old Playbook (Optional)

The old rulebook used `playbooks/find-matching-job-template.yml` which is now only called from `intelligent-aiops-workflow.yml` in a different way.

**Check usage:**
```bash
grep -r "find-matching-job-template.yml" . --exclude-dir=.git
```

**If only used by old rulebook:**
```bash
# Move to archive
mv playbooks/find-matching-job-template.yml \
   archive/old-rulebooks/
```

### Step 4: Update Documentation References

Check if any docs reference the old rulebook:

```bash
grep -r "find-template-on-unmatched-event" docs/ README.md 2>/dev/null
```

Update to reference `intelligent-remediation.yml` instead.

## What You Can Keep

**Keep these files - they're still used:**

```
ansible-aiops/
├── rulebooks/
│   └── intelligent-remediation.yml          ✅ ACTIVE
├── playbooks/
│   ├── intelligent-aiops-workflow.yml       ✅ Used by Case 5
│   ├── generate-and-push.yml                ✅ Standalone, still useful
│   └── find-matching-job-template.yml       ⚠️ Check usage first
├── test-events/
│   └── *.json                               ✅ All useful
└── docs/
    ├── AAP-JOB-TEMPLATES-SETUP.md          ✅ Current
    ├── DEPLOYMENT-GUIDE.md                 ✅ Current
    └── RULEBOOK-COMPARISON.md              ✅ Current
```

## Verification

After cleanup, verify:

```bash
# Should only show intelligent-remediation.yml
ls rulebooks/

# Output should be:
# intelligent-remediation.yml
```

## Summary

**Before cleanup:**
```
rulebooks/
├── find-template-on-unmatched-event.yml     ❌ OLD - Prototype
└── intelligent-remediation.yml              ✅ NEW - Production
```

**After cleanup:**
```
rulebooks/
└── intelligent-remediation.yml              ✅ ONLY ONE - Production
```

**Archive (optional):**
```
archive/old-rulebooks/
└── find-template-on-unmatched-event.yml     📦 Archived for reference
```

---

## Why Remove It?

1. **Confusing** - Having 2 rulebooks makes it unclear which one to use
2. **Outdated** - Old approach (run_playbook vs run_job_template)
3. **Incomplete** - Missing Maya integration, git push, etc.
4. **Not production-ready** - Just a prototype/POC
5. **Superseded** - Everything it did is done better in the new one

**Recommendation:** Archive it now, delete after 30 days if no issues.
