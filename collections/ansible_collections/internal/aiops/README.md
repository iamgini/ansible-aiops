# Ansible Collection - internal.aiops

Intelligent AIOps roles for event-driven remediation with Ansible Automation Platform.

## Roles

| Role | Description |
|------|-------------|
| `internal.aiops.aiops_mcp_matcher` | Query AAP via MCP to find and launch matching job templates |
| `internal.aiops.aiops_playbook_generator` | AI-powered playbook generation with pluggable backends |
| `internal.aiops.aiops_cac_manager` | Create AAP resources dynamically using Configuration as Code |

## Usage

```yaml
- name: Run AIOps workflow
  hosts: localhost
  tasks:
    - name: Find matching template via MCP
      ansible.builtin.include_role:
        name: internal.aiops.aiops_mcp_matcher

    - name: Generate playbook with AI
      ansible.builtin.include_role:
        name: internal.aiops.aiops_playbook_generator

    - name: Create AAP resources via CaC
      ansible.builtin.include_role:
        name: internal.aiops.aiops_cac_manager
```

## Dependencies

- `ansible.controller` >= 4.5.0 (CaC: project, job_template, workflow modules)
- `ansible.scm` >= 1.0.0 (Git operations: git_retrieve, git_publish)
- `ansible.mcp` >= 1.0.0 (MCP client for AAP integration)
