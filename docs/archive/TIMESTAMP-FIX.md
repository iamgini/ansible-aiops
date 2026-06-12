# Timestamp Fix - Dynamic vs Static Values

## The Problem

### Initial Attempt (BROKEN):
```yaml
vars:
  timestamp: "{{ lookup('pipe', 'date +%Y%m%d-%H%M%S') }}"
  temp_clone_dir: "/tmp/ansible-maya-git-{{ timestamp }}"
```

**Issue:** `lookup('pipe')` is evaluated **every time** the variable is referenced!

**Example:**
```
Task 1 (Clone): temp_clone_dir = /tmp/ansible-maya-git-20260604-123458
Task 2 (Save):  temp_clone_dir = /tmp/ansible-maya-git-20260604-123459  ❌ Different!
Task 3 (Commit): temp_clone_dir = /tmp/ansible-maya-git-20260604-123500 ❌ Different!
```

**Result:** Clone happens in one directory, but save tries to write to a different directory!

```
TASK [Save generated playbook to cloned repo]
fatal: [localhost]: FAILED! => {
  "msg": "Destination directory /tmp/ansible-maya-git-20260604-123458/playbooks does not exist"
}
```

## The Solution

### Fixed Approach (WORKING):
```yaml
tasks:
  - name: Generate unique run ID for temp directory
    ansible.builtin.set_fact:
      run_id: "{{ lookup('pipe', 'date +%Y%m%d-%H%M%S') }}"
    run_once: true

  - name: Set temp clone directory path
    ansible.builtin.set_fact:
      temp_clone_dir: "/tmp/ansible-maya-git-{{ run_id }}"
```

**How it works:**
1. First task captures the timestamp **once** into `run_id` variable
2. Second task builds the path using the **captured** `run_id`
3. All subsequent tasks use the **same** `temp_clone_dir` value

**Example:**
```
Task 1: run_id = "20260604-124628"
Task 2: temp_clone_dir = "/tmp/ansible-maya-git-20260604-124628"
Task 3 (Clone):  Uses /tmp/ansible-maya-git-20260604-124628 ✅
Task 4 (Save):   Uses /tmp/ansible-maya-git-20260604-124628 ✅
Task 5 (Commit): Uses /tmp/ansible-maya-git-20260604-124628 ✅
Task 6 (Push):   Uses /tmp/ansible-maya-git-20260604-124628 ✅
```

## Why Not Use `vars:`?

### Attempt (Still BROKEN):
```yaml
vars:
  run_id: "{{ lookup('pipe', 'date +%Y%m%d-%H%M%S') }}"
  temp_clone_dir: "/tmp/ansible-maya-git-{{ run_id }}"
```

**Issue:** Variables in `vars:` are evaluated at task runtime, not play runtime!

Each task that references `run_id` will execute the `lookup('pipe')` again, giving different values.

## Ansible Variable Evaluation Order

### 1. Static Variables (vars:)
```yaml
vars:
  static_value: "hello"          # ✅ Evaluated once
  dynamic_value: "{{ 1 + 1 }}"   # ⚠️ Evaluated at task time
```

### 2. set_fact (Captured Variables)
```yaml
tasks:
  - set_fact:
      captured_time: "{{ lookup('pipe', 'date +%s') }}"  # ✅ Evaluated once, cached
```

### 3. Lookups in Tasks
```yaml
tasks:
  - debug:
      msg: "{{ lookup('pipe', 'date +%s') }}"  # ⚠️ Evaluated every time
```

## Key Takeaway

**To capture a dynamic value once, use `set_fact`!**

❌ **Don't do this:**
```yaml
vars:
  timestamp: "{{ lookup('pipe', 'date +%Y%m%d-%H%M%S') }}"
```

✅ **Do this:**
```yaml
tasks:
  - name: Capture timestamp once
    set_fact:
      timestamp: "{{ lookup('pipe', 'date +%Y%m%d-%H%M%S') }}"
```

## Verification

### Test Run Output:
```bash
$ ansible-playbook generate-and-push.yml -v

TASK [Generate unique run ID for temp directory]
ok: [localhost] => {"ansible_facts": {"run_id": "20260604-124628"}, "changed": false}

TASK [Set temp clone directory path]
ok: [localhost] => {"ansible_facts": {"temp_clone_dir": "/tmp/ansible-maya-git-20260604-124628"}, "changed": false}

# All subsequent tasks use the same directory:
# /tmp/ansible-maya-git-20260604-124628 ✅
```

### Confirmed Working:
```
✅ Workflow Complete!
Generated Playbook: disk_full_web-server-01_example_com.yml
Confidence: 80.0%
Validation: Passed ✓
```

## Alternative: Static Directory

If you want the same directory for all runs in a day:

```yaml
tasks:
  - name: Use date-only directory
    set_fact:
      run_id: "{{ lookup('pipe', 'date +%Y%m%d') }}"
      temp_clone_dir: "/tmp/ansible-maya-git-{{ lookup('pipe', 'date +%Y%m%d') }}"
```

**Result:** `/tmp/ansible-maya-git-20260604`

**Caveat:** Only works for ONE run per day (directory already exists on second run)

## Recommendation

**Use the current implementation (date + time):**
- ✅ Unique for every run
- ✅ No conflicts
- ✅ Works with concurrent executions
- ✅ Proper cleanup after each run

**Format:** `/tmp/ansible-maya-git-YYYYMMDD-HHMMSS`

**Example:** `/tmp/ansible-maya-git-20260604-124628`
