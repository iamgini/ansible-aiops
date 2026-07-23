# Building the AIOps Execution Environment

This guide explains how to build the custom execution environment (EE) for the Intelligent AIOps workflow with Coder CLI support.

## Prerequisites

### Software Requirements

- **ansible-builder** (v3.x+)
  ```bash
  pip install ansible-builder
  ```

- **Podman** or **Docker**
  ```bash
  # RHEL/Fedora
  sudo dnf install podman
  
  # Ubuntu/Debian
  sudo apt install podman
  ```

### Registry Access (Optional)

For pushing to a container registry:
```bash
# Login to registry
podman login registry.example.com

# Or Red Hat registry
podman login registry.redhat.io
```

## Files Required

This directory contains:

```
ansible-aiops/
├── execution-environment.yml   # EE definition (ansible-builder config)
├── requirements.yml            # Ansible collections
├── requirements.txt            # Python packages
├── bindep.txt                  # System packages
└── EE-BUILD.md                 # This file
```

## Build Instructions

### 1. Verify Files

```bash
cd /home/gmadappa/ansible/ansible-aiops

# Check all required files exist
ls -la execution-environment.yml requirements.yml requirements.txt bindep.txt
```

### 2. Build Execution Environment

```bash
# Build with default settings
ansible-builder build -t aiops-ee:latest -v 3

# Build with custom tag
ansible-builder build -t aiops-ee:1.0.0 -v 3

# Build with specific context directory
ansible-builder build -t aiops-ee:latest -v 3 --context ./context
```

**Build Output:**
- Image built: `aiops-ee:latest`
- Build context: `./context/` (auto-created)
- Build logs: Verbose output with `-v 3`
- Build time: ~3-5 minutes (first build)

### 3. Verify Build

```bash
# List built images
podman images | grep aiops-ee

# Inspect image
podman inspect aiops-ee:latest

# Test run
podman run --rm aiops-ee:latest ansible --version
podman run --rm aiops-ee:latest coder version
```

### 4. Push to Registry (Optional)

```bash
# Tag for registry
podman tag aiops-ee:latest registry.example.com/aiops-ee:latest
podman tag aiops-ee:latest registry.example.com/aiops-ee:1.0.0

# Push to registry
podman push registry.example.com/aiops-ee:latest
podman push registry.example.com/aiops-ee:1.0.0
```

## What's Included

### Ansible Collections

| Collection | Version | Purpose |
|------------|---------|---------|
| `ansible.eda` | 1.0.0+ | Event-Driven Automation |
| `ansible.mcp` | 1.0.0+ | MCP client for AAP integration |
| `ansible.controller` | 4.5.0+ | AAP controller interaction, job launching |
| `ansible.utils` | 2.0.0+ | Utility functions |
| `ansible.platform` | 1.0.0+ | Platform integration |

### Python Packages

| Package | Version | Purpose |
|---------|---------|---------|
| `ansible-core` | 2.16.0+ | Ansible engine |
| `requests` | 2.31.0+ | HTTP client for API calls |
| `awxkit` | 23.0.0+ | AAP interaction library |
| `jmespath` | 1.0.0+ | JSON querying |
| `PyYAML` | 6.0+ | YAML processing |
| `GitPython` | 3.1.0+ | Git operations |

### System Packages

| Package | Purpose |
|---------|---------|
| `git` | Git repository operations |
| `curl` | Coder CLI installation, API calls |
| `openssh-clients` | SSH to Coder workspaces |
| `gcc`, `python3-devel` | Python package compilation |

### Custom Tools

- **Coder CLI** - Installed via `https://coder.com/install.sh`
- Verified at build time with `coder version`

## Using the EE

### In AAP (Ansible Automation Platform)

1. **Push to registry** (if not already done)
2. **Add to AAP**:
   - Navigate to: Administration → Execution Environments
   - Click "Add"
   - Name: `aiops-ee`
   - Image: `registry.example.com/aiops-ee:latest`
   - Pull policy: `Always` or `IfNotPresent`

3. **Configure project to use EE**:
   - Navigate to: Resources → Projects → Your AIOps Project
   - Execution Environment: Select `aiops-ee`
   - Save

4. **Use in job templates**:
   - Job templates automatically inherit project's EE
   - Or override per-template if needed

### In EDA (Event-Driven Automation)

**Configure in activation:**

```yaml
# In EDA activation settings
execution_environment:
  name: aiops-ee
  image: registry.example.com/aiops-ee:latest
  pull_policy: always
```

**Or in decision environment:**

```bash
# Update decision environment to use custom EE
ansible-eda-controller decision-environment update \
  --name aiops-de \
  --image registry.example.com/aiops-ee:latest
```

### Local Testing

```bash
# Run playbook with EE
podman run --rm -it \
  -v $(pwd):/runner:Z \
  -e RUNNER_PLAYBOOK=playbooks/intelligent-aiops-workflow.yml \
  aiops-ee:latest

# Or with ansible-navigator
ansible-navigator run playbooks/intelligent-aiops-workflow.yml \
  --execution-environment-image aiops-ee:latest \
  -m stdout
```

## Runtime Configuration

### Coder Authentication

The EE includes Coder CLI but requires authentication at runtime:

**Method 1: Environment Variables**
```bash
export CODER_URL="https://coder.example.com"
export CODER_SESSION_TOKEN="your-session-token"
```

**Method 2: Interactive Login** (not recommended for automation)
```bash
# Inside EE container
coder login https://coder.example.com
```

**Method 3: AAP Credentials**

Create custom credential type in AAP:

```yaml
# Input Configuration
fields:
  - id: coder_url
    type: string
    label: Coder URL
  - id: coder_session_token
    type: string
    label: Coder Session Token
    secret: true

# Injector Configuration
env:
  CODER_URL: '{{ coder_url }}'
  CODER_SESSION_TOKEN: '{{ coder_session_token }}'
```

### AI Backend Selection

```bash
# Default: Lightspeed API backend
export AI_BACKEND="lightspeed"
export LIGHTSPEED_URL="http://localhost:8000/api/v0/ai/generations/"
export LIGHTSPEED_TOKEN="your_token"

# Alternative: Coder backend
export AI_BACKEND="coder"
export CODER_URL="https://coder.example.com"
export CODER_SESSION_TOKEN="your_token"
```

## Troubleshooting

### Build Failures

**Issue: Coder CLI installation fails**
```
Error: curl: command not found
```

**Solution**: Verify `bindep.txt` includes `curl`:
```bash
grep curl bindep.txt
```

**Issue: Collection installation timeout**
```
Error: Failed to download collection ansible.mcp
```

**Solution**: Increase timeout or use mirror:
```yaml
# In execution-environment.yml
build_arg_defaults:
  ANSIBLE_GALAXY_SERVER_TIMEOUT: '60'
```

### Runtime Issues

**Issue: Coder CLI not authenticated**
```
Error: You are not authenticated. Run 'coder login'
```

**Solution**: Set environment variables before running playbook:
```bash
export CODER_URL="https://coder.example.com"
export CODER_SESSION_TOKEN="your-token"
```

**Issue: Collections not found**
```
ERROR! couldn't resolve module/action 'ansible.mcp.query_mcp'
```

**Solution**: Verify collections installed in EE:
```bash
podman run --rm aiops-ee:latest ansible-galaxy collection list
```

## Updating the EE

### Update Collections

1. Edit `requirements.yml` - Update version numbers
2. Rebuild: `ansible-builder build -t aiops-ee:1.1.0 -v 3`
3. Push to registry with new tag

### Update Python Packages

1. Edit `requirements.txt` - Update versions
2. Rebuild: `ansible-builder build -t aiops-ee:1.1.0 -v 3`

### Update System Packages

1. Edit `bindep.txt` - Add/remove packages
2. Rebuild

### Version Tagging Strategy

```bash
# Development builds
ansible-builder build -t aiops-ee:dev

# Release candidates
ansible-builder build -t aiops-ee:1.1.0-rc1

# Stable releases
ansible-builder build -t aiops-ee:1.1.0
ansible-builder build -t aiops-ee:latest  # Also tag as latest
```

## Best Practices

1. **Version Collections**: Pin versions in `requirements.yml` for production
2. **Tag Images**: Use semantic versioning (e.g., `1.0.0`, `1.1.0`)
3. **Test Before Push**: Run test playbooks locally before pushing to registry
4. **Update Regularly**: Rebuild EE monthly for security patches
5. **Document Changes**: Keep changelog of EE updates
6. **Multi-Stage Builds**: Keep build context clean (handled by ansible-builder)

## Resources

- **ansible-builder docs**: https://ansible.readthedocs.io/projects/builder/
- **Coder CLI**: https://coder.com/docs/cli
- **AAP EE Guide**: https://access.redhat.com/documentation/en-us/red_hat_ansible_automation_platform/

---

**Last Updated**: 2026-07-10  
**EE Version**: 1.0.0  
**Base Image**: registry.redhat.io/ansible-automation-platform-26/ee-supported-rhel9:latest
