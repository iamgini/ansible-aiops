# Timestamp Options for Temp Directory

## Current Implementation ✅

```yaml
vars:
  # Timestamp for unique temp directory (format: YYYYMMDD-HHMMSS)
  timestamp: "{{ lookup('pipe', 'date +%Y%m%d-%H%M%S') }}"
  temp_clone_dir: "/tmp/ansible-maya-git-{{ timestamp }}"
```

**Example:** `/tmp/ansible-maya-git-20260604-105523`

## Alternative Options

### Option 1: Date Only (Your Suggestion)
```yaml
vars:
  timestamp: "{{ lookup('pipe', 'date +%Y%m%d') }}"
  temp_clone_dir: "/tmp/ansible-maya-git-{{ timestamp }}"
```

**Example:** `/tmp/ansible-maya-git-20260604`

**Issue:** If you run multiple times in the same day, the directory already exists!

### Option 2: Date + Time (Current - Recommended)
```yaml
vars:
  timestamp: "{{ lookup('pipe', 'date +%Y%m%d-%H%M%S') }}"
  temp_clone_dir: "/tmp/ansible-maya-git-{{ timestamp }}"
```

**Example:** `/tmp/ansible-maya-git-20260604-105523`

**Advantage:** Unique for every run, even multiple per second

### Option 3: Date + Random String
```yaml
vars:
  timestamp: "{{ lookup('pipe', 'date +%Y%m%d') }}"
  random_id: "{{ lookup('pipe', 'uuidgen | cut -d- -f1') }}"
  temp_clone_dir: "/tmp/ansible-maya-git-{{ timestamp }}-{{ random_id }}"
```

**Example:** `/tmp/ansible-maya-git-20260604-a3f7e2b1`

**Advantage:** Guaranteed unique, human-readable date

### Option 4: Epoch Timestamp
```yaml
vars:
  timestamp: "{{ lookup('pipe', 'date +%s') }}"
  temp_clone_dir: "/tmp/ansible-maya-git-{{ timestamp }}"
```

**Example:** `/tmp/ansible-maya-git-1717476923`

**Advantage:** Guaranteed unique, sortable

**Disadvantage:** Not human-readable

### Option 5: Date with Timezone Adjustment
```yaml
vars:
  # Add 8 hours to current time
  timestamp: "{{ lookup('pipe', 'date -d \"8 hours\" +%Y%m%d-%H%M%S') }}"
  temp_clone_dir: "/tmp/ansible-maya-git-{{ timestamp }}"
```

**Example:** `/tmp/ansible-maya-git-20260604-185523` (if local time is 10:55:23)

**Use case:** If you want timestamps in a specific timezone

## Recommendation

**Use Option 2 (Current Implementation)**

Why?
- ✅ Unique for every run
- ✅ Human-readable
- ✅ Sortable (chronological order)
- ✅ No conflicts
- ✅ Works with `gather_facts: false`

## Testing

### Test Current Implementation
```bash
$ ansible-playbook generate-and-push.yml -v
# Look for: /tmp/ansible-maya-git-20260604-105523
```

### Test with Debug
Add this task after vars:

```yaml
- name: Display temp directory path
  ansible.builtin.debug:
    msg: "Temp clone directory: {{ temp_clone_dir }}"
```

### Verify Temp Directory is Created (when GIT_TOKEN is set)
```bash
$ export GIT_TOKEN=your_token
$ ansible-playbook generate-and-push.yml
$ ls -ld /tmp/ansible-maya-git-*
# Should show the directory (or be cleaned up if playbook completed)
```

### Verify Cleanup
The playbook automatically cleans up the temp directory after push:

```yaml
- name: Clean up temp clone directory
  ansible.builtin.file:
    path: "{{ temp_clone_dir }}"
    state: absent
  when: git_token | length > 0
```

So even if it creates `/tmp/ansible-maya-git-20260604-105523`, it's deleted after the push completes.

## Manual Cleanup (if needed)

If playbook fails mid-run, temp directories might accumulate:

```bash
# List all temp directories
ls -ld /tmp/ansible-maya-git-*

# Clean up all temp directories older than 1 day
find /tmp -maxdepth 1 -name "ansible-maya-git-*" -type d -mtime +1 -exec rm -rf {} \;

# Clean up all temp directories (regardless of age)
rm -rf /tmp/ansible-maya-git-*
```

## Why Not Use ansible_date_time?

With `gather_facts: false`, the `ansible_date_time` variable is not available:

```yaml
# ❌ This FAILS with gather_facts: false
temp_clone_dir: "/tmp/ansible-maya-git-{{ ansible_date_time.epoch }}"
# Error: ansible_date_time is undefined

# ✅ This WORKS with gather_facts: false
temp_clone_dir: "/tmp/ansible-maya-git-{{ lookup('pipe', 'date +%s') }}"
```

To use `ansible_date_time`, you would need:
```yaml
gather_facts: true  # or gather_facts: false with setup module
```

But that adds ~2 seconds to playbook execution for something we don't need!

## Conclusion

Current implementation (`date +%Y%m%d-%H%M%S`) is optimal:
- Fast (no fact gathering)
- Unique (timestamp to the second)
- Readable (human-friendly format)
- Clean (auto-deleted after use)
