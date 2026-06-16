# Migration Guide: ansible-maya → Red Hat Automation Code Assistant

**Date**: June 16, 2026  
**Reason**: ansible-maya archived - superseded by Red Hat Automation Code Assistant

---

## What Changed

**Before (ansible-maya):**
```yaml
url: "{{ maya_api_url }}"  # http://ansible-maya:8000/api/v1/events/generate
```

**After (Code Assistant):**
```yaml
url: "{{ lightspeed_url }}"  # AAP 2.6 Lightspeed Coding Assistant API
```

---

## Prerequisites

### 1. AAP 2.6 with Lightspeed Deployed

**Deploy Red Hat Ansible Lightspeed (containerized):**
- Follow: [AAP 2.6 Containerized Installation](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html-single/containerized_installation/index)
- Enable: **Coding Assistant** component (not just UI chat)

**Configure Backend:**
- Customer's AI endpoint, OR
- IBM watsonx, OR
- Red Hat AI/OpenShift AI

### 2. Get API Token

**From AAP UI:**
1. Login to AAP Web UI
2. Navigate: **Users → [Your Username] → Tokens**
3. Click **Add** → Create token with **write** scope
4. Copy token value

### 3. Update Environment Variables

**Edit `.env`:**
```bash
# Remove old maya variables
# AAP_MCP_SERVER_URL=...  # Keep this for MCP
# AAP_BEARER_TOKEN=...    # Keep this for MCP

# Add Lightspeed variables
LIGHTSPEED_URL="http://lightspeed-coding-assistant.internal:8000/api/v0/ai/generations/"
LIGHTSPEED_TOKEN="your_aap_bearer_token"  # Same token from step 2

# Keep Git variables
GIT_TOKEN="ghp_your_github_token"
GIT_REMOTE_URL="https://github.com/your-org/playbooks.git"
```

---

## Migration Steps

### Step 1: Update Playbook Variables

**Edit `playbooks/intelligent-aiops-workflow.yml`:**

**OLD:**
```yaml
vars:
  maya_api_url: "http://ansible-maya:8000/api/v1/events/generate"
```

**NEW:**
```yaml
vars:
  lightspeed_url: "{{ lookup('env', 'LIGHTSPEED_URL') }}"
  lightspeed_token: "{{ lookup('env', 'LIGHTSPEED_TOKEN') }}"
```

### Step 2: Update API Call Task

**Find this section (around line 120):**
```yaml
- name: Generate playbook with Ansible Maya
  ansible.builtin.uri:
    url: "{{ maya_api_url }}?multi_agent_review=true"
    method: POST
    body_format: json
    body:
      event_type: "{{ event_type }}"
      description: "{{ event_description }}"
      host: "{{ event_host }}"
      severity: "{{ event_severity }}"
      metadata:
        service: "{{ event_service | default('') }}"
        tags: "{{ event_tags | default([]) }}"
  register: maya_response
```

**REPLACE WITH:**
```yaml
- name: Generate playbook with Code Assistant
  ansible.builtin.uri:
    url: "{{ lightspeed_url }}"
    method: POST
    headers:
      Authorization: "Bearer {{ lightspeed_token }}"
      Content-Type: "application/json"
    body_format: json
    body:
      text: "{{ lightspeed_prompt }}"
  register: lightspeed_response
  when:
    - best_match is not defined or best_match.score < mcp_minimum_score
```

### Step 3: Build Lightspeed Prompt

**Add task BEFORE the API call:**
```yaml
- name: Build Lightspeed prompt from event context
  ansible.builtin.set_fact:
    lightspeed_prompt: |
      Create an Ansible playbook to remediate the following issue:
      
      Event Type: {{ event_type }}
      Description: {{ event_description }}
      Target Host: {{ event_host }}
      Severity: {{ event_severity }}
      {% if event_service is defined %}Service: {{ event_service }}{% endif %}
      
      Requirements:
      - Use FQCN (Fully Qualified Collection Names)
      - Include error handling with block/rescue
      - Add descriptive task names
      - Use become: true where needed
      - Target the host: {{ event_host }}
```

### Step 4: Update Response Parsing

**OLD (maya response):**
```yaml
playbook_content: "{{ maya_response.json.playbook }}"
confidence_score: "{{ maya_response.json.confidence_score }}"
```

**NEW (Code Assistant response):**
```yaml
- name: Extract generated playbook
  ansible.builtin.set_fact:
    playbook_content: "{{ lightspeed_response.json.playbook | default(lightspeed_response.json.content) }}"
    
# Note: Code Assistant may not return confidence scores
# Add basic validation instead
- name: Validate generated playbook
  ansible.builtin.assert:
    that:
      - playbook_content is defined
      - playbook_content | length > 0
      - "'- name:' in playbook_content"
    fail_msg: "Generated playbook is invalid or empty"
```

### Step 5: Update Git Commit Message

**OLD:**
```yaml
commit_message: "AI-generated playbook by Ansible Maya"
```

**NEW:**
```yaml
commit_message: "AI-generated playbook by Red Hat Code Assistant"
```

### Step 6: Update README References

**Edit `README.md`:**

**Remove:**
```markdown
- **[Ansible Maya](https://github.com/iamgini/ansible-maya)** - AI-powered playbook generator
```

**Add:**
```markdown
- **Red Hat Automation Code Assistant** - Enterprise AI-powered playbook generation (AAP 2.6+)
```

---

## Testing

### Test 1: Direct API Call

```bash
# Test Code Assistant endpoint
curl -X POST "http://lightspeed-coding-assistant:8000/api/v0/ai/generations/" \
  -H "Authorization: Bearer ${LIGHTSPEED_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Create a playbook to check disk usage on all hosts"
  }'
```

**Expected response:**
```json
{
  "playbook": "---\n- name: Check disk usage\n  hosts: all\n  tasks:\n    - name: Get disk usage\n      ..."
}
```

### Test 2: Run Updated Workflow

```bash
# Send test event
curl -X POST http://localhost:5000/webhook \
  -H "Content-Type: application/json" \
  -d @test-events/disk-full.json

# Check logs
tail -f /var/log/ansible-eda/rulebook.log
```

### Test 3: Verify Git Commit

```bash
# Check generated playbooks repo
cd /path/to/playbooks-repo
git log --oneline | head -5

# Should see: "AI-generated playbook by Red Hat Code Assistant"
```

---

## Troubleshooting

### Issue: "401 Unauthorized"
**Cause**: Invalid or expired token  
**Fix**: Regenerate token in AAP UI (Users → Tokens)

### Issue: "Connection refused"
**Cause**: Lightspeed service not running  
**Fix**: Check AAP containerized deployment status
```bash
podman ps | grep lightspeed
# or
kubectl get pods -n aap | grep lightspeed
```

### Issue: Empty/Invalid playbook response
**Cause**: Prompt too vague or backend AI not configured  
**Fix**: 
1. Check Lightspeed backend configuration (AI endpoint)
2. Make prompt more specific (add examples)
3. Check AAP logs: `journalctl -u automation-controller -f`

### Issue: "Connection timeout"
**Cause**: Backend AI endpoint slow/unreachable  
**Fix**: 
- Increase timeout in playbook: `timeout: 60`
- Check customer AI endpoint health
- Verify network connectivity

---

## Rollback Plan

If migration fails, revert to ansible-maya:

```bash
# 1. Restore old playbook from git
git checkout HEAD~1 playbooks/intelligent-aiops-workflow.yml

# 2. Restore old environment
export MAYA_API_URL="http://ansible-maya:8000/api/v1/events/generate"

# 3. Restart ansible-maya service
docker-compose -f /path/to/ansible-maya/docker-compose.yml up -d
```

---

## Cleanup (After Successful Migration)

```bash
# Stop ansible-maya service
docker-compose -f /path/to/ansible-maya/docker-compose.yml down

# Remove old environment variables
# Edit .env - remove MAYA_API_URL

# Update documentation
git commit -am "chore: migrate from ansible-maya to Code Assistant"
```

---

## Reference

- **AAP 2.6 Docs**: [Containerized Installation](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html-single/containerized_installation/index)
- **Code Assistant API**: Internal AAP docs (check with Red Hat team)
- **ansible-maya Archive**: [github.com/iamgini/ansible-maya](https://github.com/iamgini/ansible-maya) (branch: archive/original-implementation)

---

## Questions?

- **Internal**: Check with Red Hat AAP product team
- **Lightspeed Setup**: AAP 2.6 containerized installation guide
- **API Issues**: Check AAP controller logs and Lightspeed service status
