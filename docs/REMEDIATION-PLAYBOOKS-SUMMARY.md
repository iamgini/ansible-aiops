# Remediation Playbooks Summary

## Final Structure ✅

```
playbooks/
├── remediation_disk-cleanup.yml             Case 1 (170 lines)
├── remediation_restart-service.yml          Case 2 (121 lines)
├── remediation_investigate-cpu.yml          Case 3 (214 lines)
├── remediation_renew-certificate.yml        Case 4 (213 lines)
├── intelligent-aiops-workflow.yml           Case 5 (AI Intelligence)
├── cac-create-jt.yml                        Post-review CaC (creates JT/WF)
└── generate-and-push.yml                    Standalone tool

archive/old-playbooks/                        📦 Archived
├── execute-aap-job-template.yml             (No longer needed)
├── find-matching-job-template.yml           (Superseded by internal.aiops.aiops_mcp_matcher role)
└── find-template-on-unmatched-event.yml     (Old rulebook)
```

## Cleanup Actions Taken

### ❌ Removed (Archived)
1. `execute-aap-job-template.yml` - No longer needed (rulebook uses `run_job_template` directly)
2. `find-matching-job-template.yml` - Superseded by `internal.aiops.aiops_mcp_matcher` role (uses `ansible.mcp.run_tool`)

### ✅ Created
4 production-ready remediation playbooks for AAP job templates

### ✅ Kept
- `intelligent-aiops-workflow.yml` - Used by Case 5 (unknown events)
- `generate-and-push.yml` - Useful standalone tool for manual playbook generation

---

## Playbook Details

### 1. disk-cleanup.yml (Case 1)

**AAP Job Template:** `Remediate Disk Space`

**Purpose:** Clean up disk space when usage exceeds threshold

**Features:**
- ✅ Identifies large directories with `du`
- ✅ Cleans package manager cache (DNF/YUM/APT)
- ✅ Removes old log files (configurable retention)
- ✅ Truncates large log files (>100MB)
- ✅ Cleans systemd journal
- ✅ Removes old temp files
- ✅ Removes core dumps
- ✅ Reports space freed percentage
- ✅ Fails if cleanup insufficient for critical events

**Input Variables:**
```yaml
event_type: disk_full
event_severity: high
partition: /var
usage_percent: 95
```

**Cleanup Actions:**
- Package cache (DNF/YUM/APT)
- Log files older than 30 days
- Large log files truncated to 0
- Journal logs (vacuum to 500MB)
- Temp files older than 7 days
- Core dumps older than 7 days

---

### 2. restart-service.yml (Case 2)

**AAP Job Template:** `Restart Service`

**Purpose:** Restart failed services automatically

**Features:**
- ✅ Verifies service exists before attempting restart
- ✅ Captures service logs before/after restart
- ✅ Retries restart up to 3 times with delays
- ✅ Daemon reload for systemd services
- ✅ Waits for service to stabilize
- ✅ Verifies service is running post-restart
- ✅ Ensures service is enabled
- ✅ Provides detailed remediation summary

**Input Variables:**
```yaml
event_type: service_down
event_severity: critical
service_name: httpd
```

**Retry Logic:**
- Max attempts: 3
- Delay between attempts: 5 seconds
- Stabilization wait: 10 seconds

---

### 3. investigate-cpu.yml (Case 3)

**AAP Job Template:** `Investigate High CPU`

**Purpose:** Investigate and remediate high CPU usage

**Features:**
- ✅ Captures current CPU usage and load average
- ✅ Identifies top 20 CPU-consuming processes
- ✅ Detects runaway processes (>95% CPU)
- ✅ Identifies zombie processes
- ✅ Checks I/O wait statistics
- ✅ Monitors memory usage
- ✅ Auto-kills runaway processes (critical severity only)
- ✅ Restarts hung services
- ✅ Cleans up zombie processes
- ✅ Generates investigation report

**Input Variables:**
```yaml
event_type: high_cpu
event_severity: warning
cpu_threshold: 80
duration_minutes: 10
```

**Auto-Remediation (Critical Severity Only):**
- Kill processes using >95% CPU
- Restart identified hung services
- Clean up zombie processes

**Report Location:** `/tmp/cpu_investigation_<timestamp>.txt`

---

### 4. renew-certificate.yml (Case 4)

**AAP Job Template:** `Renew SSL Certificate`

**Purpose:** Renew expiring SSL certificates

**Features:**
- ✅ Validates certificate existence
- ✅ Extracts certificate information (expiry, issuer, subject)
- ✅ Calculates actual days until expiry
- ✅ Detects Let's Encrypt certificates automatically
- ✅ Auto-renews Let's Encrypt certs with certbot
- ✅ Generates CSR for custom certificates
- ✅ Reloads web server after renewal
- ✅ Tests HTTPS connectivity
- ✅ Generates renewal report

**Input Variables:**
```yaml
event_type: certificate_expiry
event_severity: high
cert_path: /etc/ssl/certs/server.crt
days_until_expiry: 30
web_service: httpd  # or nginx, apache2
```

**Certificate Types Supported:**
- **Let's Encrypt:** Automatic renewal with certbot
- **Custom/CA:** Generates CSR for manual renewal

**Report Location:** `/tmp/cert_renewal_<timestamp>.txt`

---

## Mapping to AAP Job Templates

| # | EDA Rulebook Case | Playbook | AAP Job Template Name |
|---|-------------------|----------|----------------------|
| 1 | High Disk Usage | `remediation_disk-cleanup.yml` | `Remediate Disk Space` |
| 2 | Service Down | `remediation_restart-service.yml` | `Restart Service` |
| 3 | High CPU | `remediation_investigate-cpu.yml` | `Investigate High CPU` |
| 4 | Certificate Expiry | `remediation_renew-certificate.yml` | `Renew SSL Certificate` |
| 5 | Unknown Event | `intelligent-aiops-workflow.yml` | `AI Intelligence - Unknown Event Remediation` |

---

## Usage in AAP

### Create AAP Project

1. **AAP UI** → Projects → Add
2. **Name:** `ansible-aiops`
3. **SCM Type:** Git
4. **SCM URL:** `https://github.com/iamgini/ansible-aiops`
5. **SCM Branch:** `main`
6. **Update on Launch:** ✅ Yes

### Create Job Templates

For each of the 4 remediation playbooks:

1. **AAP UI** → Templates → Add → Job Template
2. **Project:** `ansible-aiops`
3. **Playbook:** `playbooks/remediation_<playbook-name>.yml`
4. **Inventory:** Your production inventory
5. **Credentials:** Machine credential for target hosts
6. **Prompt on Launch:**
   - ✅ Limit (to target specific hosts)
   - ✅ Extra Variables (to pass event data)

### Example Extra Variables

When EDA launches the job template, it passes event data:

```yaml
# For disk-cleanup.yml
event_type: "disk_full"
event_severity: "high"
partition: "/var"
usage_percent: 95

# For restart-service.yml
event_type: "service_down"
event_severity: "critical"
service_name: "httpd"

# For investigate-cpu.yml
event_type: "high_cpu"
event_severity: "warning"
cpu_threshold: 80
duration_minutes: 10

# For renew-certificate.yml
event_type: "certificate_expiry"
event_severity: "high"
cert_path: "/etc/ssl/certs/server.crt"
days_until_expiry: 30
web_service: "httpd"
```

---

## Testing Playbooks

### Test Locally (Optional)

```bash
# Test disk cleanup
ansible-navigator run playbooks/remediation_disk-cleanup.yml -m stdout \
  -i localhost, \
  -e "partition=/tmp usage_percent=50"

# Test service restart
ansible-navigator run playbooks/remediation_restart-service.yml -m stdout \
  -i localhost, \
  -e "service_name=chronyd"

# Test CPU investigation
ansible-navigator run playbooks/remediation_investigate-cpu.yml -m stdout \
  -i localhost, \
  -e "cpu_threshold=50"

# Test certificate renewal
ansible-navigator run playbooks/remediation_renew-certificate.yml -m stdout \
  -i localhost, \
  -e "cert_path=/etc/ssl/certs/ca-bundle.crt"
```

### Test via AAP

1. Navigate to AAP job template
2. Click "Launch"
3. Specify limit (target host)
4. Add extra variables
5. Click "Launch"
6. Monitor job output

---

## Dependencies

### Required Collections

```yaml
# requirements.yml
collections:
  - name: community.crypto
    version: ">=2.0.0"  # For certificate operations
  - name: ansible.posix
    version: ">=1.0.0"  # For service facts
```

### Install Collections

```bash
ansible-galaxy collection install -r requirements.yml
```

Or in AAP, add to project requirements.

---

## Summary Statistics

| Metric | Count |
|--------|-------|
| **Total Playbooks** | 4 remediation + 3 workflows = 7 |
| **Total Lines** | 718 (remediation only) |
| **Average Complexity** | 180 lines per playbook |
| **Test Events** | 4 (one per remediation case) |
| **AAP Job Templates** | 6 (4 remediation + 1 AI + 1 post-review CaC) |
| **Archived Files** | 3 (old/superseded playbooks) |

---

## Next Steps

1. ✅ **Done:** 4 remediation playbooks created
2. ⏸️ **Your turn:** Create 5 AAP job templates
3. ⏸️ **Your turn:** Test each template with sample events
4. ⏸️ **Your turn:** Activate EDA rulebook in AAP
5. ⏸️ **Your turn:** Configure event sources (Prometheus, etc.)

**Status:** Ready for AAP deployment! 🚀
