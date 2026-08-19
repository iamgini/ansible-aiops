# TODO - Ansible AIOps

## End-to-End Pipeline

```
Repos:
  - ansible-aiops: automation engine (this repo)
  - ansible-ai-generated-playbooks: generated playbook output (https://github.com/iamgini/ansible-ai-generated-playbooks)

Event → MCP matcher → no match found
→ AI generates playbook → push to ansible-ai-generated-playbooks on unique branch (aiops_review/<event>_<host>_<timestamp>)
→ AI review: another/same AI model reviews the playbook, pushes changes/suggestions to <branch>_review
→ PR/MR created automatically with event context
→ AAP WF pauses (approval node) — waits for human review
→ User reviews code in Git, customer CI/CD runs unit tests
→ User merges to main
→ User approves AAP WF
→ Next JT in WF does CaC — creates JT only (no WF needed, see note below)
→ Success → operator manually promotes JT for future MCP matching
→ Unpromoted JTs cleaned up after N days

NOTE: CaC step creates only the JT pointing to the merged playbook.
No WF wrapping needed — the remediation JT is launched directly by MCP matcher on future events.
```

## Phase 1: Git-Based Review Workflow

- [ ] Update `git_push.yml` to push to `ansible-ai-generated-playbooks` repo on unique branch (`aiops_review/<event_type>_<host>_<timestamp>`) instead of `main`
- [ ] Create PR/MR automatically (GitHub/GitLab API) with event context in description
- [ ] Add placeholder playbook in `main` branch with debug task ("Waiting for Review and Merge")
- [ ] Each concurrent event gets its own branch and PR — no collision

## Phase 2: EDA Git Webhook Listener

- [ ] Create EDA rulebook to listen for git merge/push webhooks on `main` branch
- [ ] Extract merged playbook filename from webhook payload
- [ ] Trigger CaC playbook to create JT + launch WF

## Phase 3: Dynamic JT/WF Creation via CaC (Post-Review)

- [ ] Create CaC playbook using `ansible.platform` to:
  - [ ] Create JT pointing to the merged playbook (project: ansible-ai-generated-playbooks, branch: main)
  - [ ] Create WF containing the new JT
  - [ ] Launch the WF
- [ ] RBAC: use a dedicated service account with Project Admin, JT Admin, WF Admin, Execute roles
- [ ] Reference CaC patterns from `ansible-aap-cac` (filetree-based configuration)

## Phase 4: Promotion (Manual)

- [ ] After successful job run, operator manually promotes the JT to permanent
- [ ] Promoted JTs become available for future MCP template matching (self-improving system)
- [ ] Define promotion mechanism (e.g., tag JT as `promoted`, or rename with `remediation_` prefix)
- [ ] Promoted JTs excluded from cleanup

## Phase 5: Cleanup

- [ ] Scheduled job to purge unpromoted JTs older than N days
- [ ] Clean up merged branches (`aiops_review/*`)
- [ ] Optionally archive unpromoted generated playbooks

## MCP Optional Mode

- [ ] MCP must be optional — support regex-based template matching as fallback when MCP is not available
- [ ] Use regex match against AAP job template names/descriptions (via `ansible.controller` API directly)
- [ ] Toggle via variable (e.g., `use_mcp: true/false`) — default to MCP when available, fall back to regex

## CI/CD for Generated Playbooks

- [ ] Set up Molecule scenario in `ansible-ai-generated-playbooks` repo (skeleton in `docs/samples/molecule/`)
- [ ] Set up GitLab CI pipeline (sample in `docs/samples/gitlab-ci-molecule.yml`)
- [ ] Configure GitLab "Pipelines must succeed" to block MR merge on failure
- [x] Decided against pytest for playbook logic validation — ansible-lint covers structural checks, human review covers logic. AI-generated pytest would just validate its own assumptions.

## Future Considerations

- [ ] Auto-promote after N successful runs of same event type (threshold-based)
- [ ] Metrics: track promotion rate, success rate of AI-generated vs promoted playbooks
- [ ] CMDB integration (ServiceNow, NetBox) for host-to-reviewer team mapping
- [ ] Multi-org support — scope JTs to correct AAP organization based on host/team
