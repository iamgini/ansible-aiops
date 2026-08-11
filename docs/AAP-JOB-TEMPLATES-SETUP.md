# AAP Job Templates Setup Guide

## Overview

You need to create **5 AAP job templates** that the EDA rulebook will launch:

- **4 Known Event Templates** (Cases 1-4) - Direct remediation playbooks
- **1 AI Intelligence Template** (Case 5) - MCP + Maya workflow

## Required Job Templates

### Job Template 1: Remediate Disk Space

**Purpose:** Clean up disk space on hosts with high disk usage

**Details:**
- **Name:** `Remediate Disk Space`
- **Job Type:** Run
- **Inventory:** Production Linux (or your target inventory)
- **Project:** Your Ansible project with remediation playbooks
- **Playbook:** `disk-cleanup.yml` (you create this)
- **Credentials:** Machine credential for target hosts
- **Variables:** (Prompted)
  ```yaml
  event_type: disk_full
  event_host: "{{ limit }}"
  event_severity: high
  partition: /var
  usage_percent: 95
  ```
- **Prompt on Launch:**
  - ✅ Limit
  - ✅ Extra Variables

**Example Playbook (`disk-cleanup.yml`):**
```yaml
---
- name: Remediate Disk Space
  hosts: all
  become: true
  tasks:
    - name: Clean package cache
      package:
        clean: yes

    - name: Remove old logs
      find:
        paths: /var/log
        patterns: "*.log"
        age: 30d
      register: old_logs

    - name: Delete old logs
      file:
        path: "{{ item.path }}"
        state: absent
      loop: "{{ old_logs.files }}"
```

---

### Job Template 2: Restart Service

**Purpose:** Restart failed services

**Details:**
- **Name:** `Restart Service`
- **Job Type:** Run
- **Inventory:** Production Linux
- **Project:** Your Ansible project
- **Playbook:** `restart-service.yml` (you create this)
- **Credentials:** Machine credential
- **Variables:** (Prompted)
  ```yaml
  event_type: service_down
  event_host: "{{ limit }}"
  event_severity: critical
  service_name: httpd
  ```
- **Prompt on Launch:**
  - ✅ Limit
  - ✅ Extra Variables

**Example Playbook (`restart-service.yml`):**
```yaml
---
- name: Restart Service
  hosts: all
  become: true
  tasks:
    - name: Restart service
      service:
        name: "{{ service_name }}"
        state: restarted

    - name: Verify service is running
      service_facts:

    - name: Check service status
      assert:
        that:
          - ansible_facts.services[service_name ~ '.service'].state == 'running'
        fail_msg: "Service {{ service_name }} failed to start"
```

---

### Job Template 3: Investigate High CPU

**Purpose:** Investigate and troubleshoot high CPU usage

**Details:**
- **Name:** `Investigate High CPU`
- **Job Type:** Run
- **Inventory:** Production Linux
- **Project:** Your Ansible project
- **Playbook:** `investigate-cpu.yml` (you create this)
- **Credentials:** Machine credential
- **Variables:** (Prompted)
  ```yaml
  event_type: high_cpu
  event_host: "{{ limit }}"
  event_severity: warning
  cpu_threshold: 80
  duration_minutes: 10
  ```
- **Prompt on Launch:**
  - ✅ Limit
  - ✅ Extra Variables

**Example Playbook (`investigate-cpu.yml`):**
```yaml
---
- name: Investigate High CPU
  hosts: all
  become: true
  tasks:
    - name: Get top CPU processes
      shell: ps aux --sort=-%cpu | head -20
      register: top_processes

    - name: Display top processes
      debug:
        var: top_processes.stdout_lines

    - name: Check system load
      shell: uptime
      register: system_load

    - name: Restart high CPU services if identified
      # Add your logic here
      debug:
        msg: "Manual intervention required"
```

---

### Job Template 4: Renew SSL Certificate

**Purpose:** Renew expiring SSL certificates

**Details:**
- **Name:** `Renew SSL Certificate`
- **Job Type:** Run
- **Inventory:** Production Linux
- **Project:** Your Ansible project
- **Playbook:** `renew-certificate.yml` (you create this)
- **Credentials:** Machine credential
- **Variables:** (Prompted)
  ```yaml
  event_type: certificate_expiry
  event_host: "{{ limit }}"
  event_severity: high
  cert_path: /etc/ssl/certs/server.crt
  days_until_expiry: 30
  ```
- **Prompt on Launch:**
  - ✅ Limit
  - ✅ Extra Variables

**Example Playbook (`renew-certificate.yml`):**
```yaml
---
- name: Renew SSL Certificate
  hosts: all
  become: true
  tasks:
    - name: Check certificate expiry
      openssl_certificate_info:
        path: "{{ cert_path }}"
      register: cert_info

    - name: Renew with certbot (if Let's Encrypt)
      command: certbot renew
      when: "'letsencrypt' in cert_path"

    - name: Reload web server
      service:
        name: httpd
        state: reloaded
```

---

### Job Template 5: AI Intelligence - Unknown Event Remediation

**Purpose:** Handle unknown events using AI intelligence (MCP + Maya)

**Details:**
- **Name:** `AI Intelligence - Unknown Event Remediation`
- **Job Type:** Run
- **Inventory:** localhost (runs on AAP controller)
- **Project:** ansible-aiops project
- **Playbook:** `playbooks/intelligent-aiops-workflow.yml`
- **Credentials:**
  - Machine credential (localhost)
  - Source Control credential (for Git push)
  - Custom credential for AAP MCP (if needed)
- **Variables:** (Prompted)
  ```yaml
  event_type: unknown
  event_description: ""
  event_host: localhost
  event_severity: medium
  event_service: ""
  event_tags: []
  event_metric: ""
  event_value: ""
  ai_review_enabled: false        # Enable AI review of generated playbook
  cac_after_code_review: true     # Defer CaC until after code review
  mcp_api_fallback: true          # Fall back to AAP REST API if MCP unavailable
  cac_create_workflow: true       # Set false to create JT only (no workflow)
  ```
- **Prompt on Launch:**
  - ✅ Extra Variables
- **Environment Variables:**
  ```yaml
  AAP_MCP_SERVER_URL: https://aap.example.com:8448/job_management/mcp
  AAP_BEARER_TOKEN: <from credential>
  GIT_TOKEN: <from credential>
  GIT_USERNAME: your_github_username
  GIT_EMAIL: your_email@example.com
  CONTROLLER_HOST: <AAP host>
  CONTROLLER_USERNAME: <from credential>
  CONTROLLER_PASSWORD: <from credential>
  ```

**Note:** This job template uses the playbook you already have: `intelligent-aiops-workflow.yml`

---

### Job Template 6: CaC - Create Job Template (Post-Review)

**Purpose:** Create AAP job template and optional workflow after code review of an AI-generated playbook. Used when `cac_after_code_review=true` (the default) to run CaC creation as a separate step after the generated playbook has been reviewed.

**Details:**
- **Name:** `AIOps - Create Job Template`
- **Job Type:** Run
- **Inventory:** localhost
- **Project:** ansible-aiops project
- **Playbook:** `playbooks/cac-create-jt.yml`
- **Credentials:**
  - Machine credential (localhost)
  - AAP credential (for controller API access)
  - Source Control credential (for Git access)
- **Variables:** (Prompted)
  ```yaml
  event_type: ""
  review_branch: ""               # The git branch containing the reviewed playbook
  cac_create_workflow: true        # Set false to create JT only (no workflow)
  ```
- **Prompt on Launch:**
  - Extra Variables

**Note:** This template is launched manually (or via automation) after the AI-generated playbook has been reviewed and approved. It creates the AAP job template (and optionally the approval workflow) pointing to the reviewed branch.

---

## Setup Steps

### Step 1: Create Remediation Playbooks (Cases 1-4)

```bash
# In your AAP project repository
mkdir -p playbooks/remediation

# Create the 4 remediation playbooks
# (Use the examples above as templates)
```

### Step 2: Create AAP Project

1. **AAP UI** → Projects → Add
2. **Name:** "Remediation Playbooks"
3. **SCM Type:** Git
4. **SCM URL:** Your git repository
5. **SCM Branch:** main
6. **Update on Launch:** ✅ Yes

### Step 3: Create Job Templates 1-4

For each of the 4 remediation templates:

1. **AAP UI** → Templates → Add → Job Template
2. Fill in details (name, inventory, project, playbook)
3. **Enable:** Prompt on Launch → Limit
4. **Enable:** Prompt on Launch → Extra Variables
5. **Save**

### Step 4: Create Job Template 5 (AI Intelligence)

1. **AAP UI** → Templates → Add → Job Template
2. **Name:** `AI Intelligence - Unknown Event Remediation`
3. **Inventory:** localhost (or create one)
4. **Project:** ansible-aiops project
5. **Playbook:** `playbooks/intelligent-aiops-workflow.yml`
6. **Enable:** Prompt on Launch → Extra Variables
7. **Add Environment Variables:**
   - AAP_MCP_SERVER_URL
   - GIT_TOKEN (use credential)
   - etc.
8. **Save**

### Step 5: Test Each Template Manually

Test via **AAP UI** → Templates → "Remediate Disk Space" → Launch → Add extra variables:
```yaml
event_host: test-server
```

### Step 6: Configure EDA to Use Your AAP

Update EDA controller configuration:

```yaml
# In AAP → Automation Decisions → Decision Environments
automation_controller_host: https://your-controller.example.com
automation_controller_token: <your_token>
```

### Step 7: Activate Rulebook in AAP

1. **Create Event Stream credential:** AAP UI → Automation Decisions → Credentials → Create
   - **Name:** `eda-webhook`
   - **Credential Type:** `Basic Event Stream`
   - **Username/Password:** Set your values
2. **Create Event Stream:** AAP UI → Automation Decisions → Event Streams → Create
   - **Name:** `AIOps Webhook`
   - **Credential:** `eda-webhook` (created above)
   - **Note:** Copy the generated Event Stream URL for configuring external sources
3. **Create Rulebook Activation:** AAP UI → Automation Decisions → Rulebook Activations → Create
   - **Name:** `Intelligent Remediation`
   - **Project:** `ansible-aiops`
   - **Rulebook:** `rulebooks/intelligent-remediation.yml`
   - **Decision Environment:** Default Decision Environment
   - **Event Stream:** `AIOps Webhook` (created above)
   - **Credential:** AAP credential (for job template launches)
   - **Restart Policy:** `On failure`
4. **Activate**

---

## Environment Variable Configuration

### For Job Template 5 (AI Intelligence)

Create two **Custom Credential Types**:

**Credential Type 1: AAP MCP**

**Input Configuration:**
```yaml
fields:
  - id: mcp_server_url
    type: string
    label: AAP MCP Server URL
  - id: aap_bearer_token
    type: string
    label: AAP Bearer Token
    secret: true
```

**Injector Configuration:**
```yaml
env:
  AAP_MCP_SERVER_URL: "{{ mcp_server_url }}"
  AAP_BEARER_TOKEN: "{{ aap_bearer_token }}"
```

**Credential Type 2: Git SCM**

**Input Configuration:**
```yaml
fields:
  - id: git_username
    type: string
    label: Git Username
    default: your_git_username
  - id: git_token
    type: string
    label: Git Token or Password
    help_text: "Personal access token (GitHub/GitLab/Bitbucket) or password"
    secret: true
  - id: git_email
    type: string
    label: Git Email
    default: your_email@example.com
```

**Injector Configuration:**
```yaml
env:
  GIT_TOKEN: "{{ git_token }}"
  GIT_USERNAME: "{{ git_username }}"
  GIT_EMAIL: "{{ git_email }}"
```

Then attach both credentials (`AAP MCP` and `Git SCM`) to Job Template 5.

---

## Testing Workflow

See [Testing with curl - Sample Events](../tests/TESTING-CURL-EVENTS.md) for all test cases (debug, Cases 1-5, Elastic-style alerts).

---

## Summary

**6 Job Templates to Create:**

1. `Remediate Disk Space` - Disk cleanup
2. `Restart Service` - Service restart
3. `Investigate High CPU` - CPU troubleshooting
4. `Renew SSL Certificate` - Certificate renewal
5. `AI Intelligence - Unknown Event Remediation` - MCP + AI workflow
6. `AIOps - Create Job Template` - Post-review CaC (creates JT/WF from reviewed playbook)

**EDA Rulebook:**
- ✅ `intelligent-remediation.yml` - Routes events to job templates

**Execution Flow:**
```
Event → EDA Webhook → Rulebook Match → AAP Job Template Launch → Remediation
```

No local ansible-playbook execution needed - everything runs in AAP! 🎉
