# Molecule and CI Testing for AI-Generated Playbooks

Testing setup for the `ansible-ai-generated-playbooks` repository.
Validates AI-generated playbooks before human review and merge.

## Testing Strategy

| Layer | Tool | What it catches | Runs in |
|---|---|---|---|
| 1 | yamllint | YAML syntax errors | AI generator + GitLab CI |
| 2 | ansible-playbook --syntax-check | Ansible syntax errors | AI generator + GitLab CI |
| 3 | ansible-lint | Best practice violations (FQCN, changed_when, become, etc.) | AI generator + GitLab CI |
| 4 | Molecule (delegated) | Playbook runs without errors in check mode | GitLab CI |
| 5 | Human review | Logic correctness, right approach for the event | Git MR |
| 6 | AAP approval node | Execution authorization | AAP workflow |

Layers 1-3 run twice: first in the AI generator role (`validate_playbook.yml` with retry loop),
then again in GitLab CI as a gate before merge.

### Why not pytest?

AI-generated pytest would validate the AI's own assumptions. ansible-lint already covers
structural checks. Logic correctness requires human judgment.

## Sample Files

All samples are in `docs/samples/` in this repo. Copy them to the generated playbooks repo.

```
docs/samples/
  gitlab-ci-molecule.yml    -> .gitlab-ci.yml
  molecule/default/
    molecule.yml             -> molecule/default/molecule.yml
    converge.yml             -> molecule/default/converge.yml
    verify.yml               -> molecule/default/verify.yml
```

## Setup

### 1. Copy files to the generated playbooks repo

```bash
cd /path/to/ansible-ai-generated-playbooks

# GitLab CI
cp /path/to/ansible-aiops/docs/samples/gitlab-ci-molecule.yml .gitlab-ci.yml

# Molecule scenario
mkdir -p molecule/default
cp /path/to/ansible-aiops/docs/samples/molecule/default/*.yml molecule/default/
```

### 2. Configure GitLab to require passing pipelines

Settings - Merge Requests - "Pipelines must succeed" - enable.

This blocks MR merge when any CI stage fails.

### 3. Pipeline flow

```
AI pushes to aiops/* branch
       |
       v
  detect-playbook (finds changed .yml files vs main)
       |
       v
  +----+----+-------------+
  |         |             |
yamllint  syntax-check  ansible-lint
  |         |             |
  +----+----+-------------+
       |
       v
  molecule-delegated (imports playbook, runs in check mode)
       |
       v
  Pipeline pass/fail
       |
       v
  Operator reviews MR -> merges to main
```

## How It Works

### Playbook Detection

The CI detects which playbook changed on the branch by diffing against main:

```bash
git diff --name-only origin/main -- playbooks/ | grep '\.yml$'
```

Since each AI-generated branch contains exactly one new playbook, this returns just that file.

### Molecule Converge

The CI symlinks the detected playbook to a known path:

```bash
ln -sf "$(pwd)/$PLAYBOOK" molecule/default/playbook_under_test.yml
```

Then Molecule's `converge.yml` imports it:

```yaml
- name: Import the playbook under test
  ansible.builtin.import_playbook: playbook_under_test.yml
```

This runs the playbook through Molecule's delegated driver on localhost.

### Molecule Verify

After converge, `verify.yml` runs post-execution assertions.
The sample provides a placeholder - extend with environment-specific checks.

## Molecule Drivers

The sample GitLab CI includes three driver options:

| Driver | Infrastructure needed | Use case |
|---|---|---|
| Delegated (default) | None - runs on CI runner | Basic validation, check mode |
| Podman | Runner with Podman | Functional tests against containers |
| Docker | Docker-in-Docker service | GitHub-hosted or Docker-based runners |

Only the delegated option is enabled by default. Uncomment others in `.gitlab-ci.yml` as needed.

## Custom Execution Environment

For AAP 2.7 (which doesn't include ansible-lint/yamllint), use the custom EE:

```
ansible-aap-demos/ansible-ee-aiops/execution-environment.yml
```

This EE includes yamllint, ansible-lint, and molecule on top of the AAP 2.7 base image.

## Validation in the AI Generator

The AI generator role (`aiops_playbook_generator`) runs validation before pushing:

1. Generates playbook via AI backend
2. Runs yamllint + syntax-check + ansible-lint (`validate_playbook.yml`)
3. If validation fails, feeds errors back to the AI and retries (up to `ai_max_retries`, default 3)
4. Only pushes to git after validation passes (or if `ai_skip_validation=true`)

This means most issues are caught before the code even reaches GitLab CI.
The CI serves as a second gate and catches anything the generator missed.
