# Coder + Claude Code Integration for AIOps

This document describes how to use **Coder cloud development environments** with **Claude Code CLI** for AI-powered Ansible playbook generation in the Intelligent AIOps workflow.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Setup](#setup)
  - [1. Coder Installation](#1-coder-installation)
  - [2. Coder Template Configuration](#2-coder-template-configuration)
  - [3. Claude Code Setup](#3-claude-code-setup)
  - [4. Environment Configuration](#4-environment-configuration)
- [Usage](#usage)
- [Workflow Details](#workflow-details)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)
- [Comparison with API-based Approach](#comparison-with-api-based-approach)

## Overview

This integration replaces direct API calls to Red Hat Automation Code Assistant with a **Coder workspace + Claude Code CLI** approach. Instead of sending a prompt to an API endpoint and receiving generated code, this workflow:

1. Creates an isolated Coder development environment (containerized workspace)
2. Executes Claude Code CLI within that workspace
3. Allows Claude Code to interact with git, run tests (ansible-lint), and commit changes
4. Provides full repository context to the AI (not just a single prompt)

**Key Benefits:**

- **Isolated execution**: Each event gets a fresh, containerized workspace
- **Full repository context**: Claude Code can read existing playbooks, roles, and collections
- **Testing integration**: Run ansible-lint, syntax checks, or even molecule tests before committing
- **Git integration**: Automatic commit and push with proper attribution
- **Multi-file changes**: Can generate roles, variables, inventories (not just single playbooks)
- **Reproducible environments**: Coder templates ensure consistent dependencies and configuration

## Architecture

```
┌─────────────┐
│ EDA Rulebook│
│   Event     │
└──────┬──────┘
       │
       ▼
┌──────────────────────────────────────────┐
│ intelligent-aiops-workflow-coder.yml     │
│                                          │
│ 1. Query AAP MCP for matching templates │
│    ↓ (no match)                          │
│ 2. Create Coder workspace                │
│    ↓                                     │
│ 3. Execute Claude Code CLI via SSH      │
│    ↓                                     │
│ 4. Verify playbook generation           │
│    ↓                                     │
│ 5. Cleanup workspace (optional)          │
└──────────────────────────────────────────┘
       │
       ▼
┌──────────────────────┐      ┌─────────────────┐
│  Coder Workspace     │      │  Git Repository │
│  ┌────────────────┐  │      │                 │
│  │ Claude Code    │  │      │  playbooks/     │
│  │ + Ansible Core │──┼──────▶  ├─ generated1  │
│  │ + Collections  │  │      │  ├─ generated2  │
│  │ + Git          │  │      │  └─ ...         │
│  └────────────────┘  │      └─────────────────┘
└──────────────────────┘
```

**Flow:**

1. **Event triggers** EDA rulebook
2. **MCP query** checks for existing job templates
3. **If no match**: Create Coder workspace with event context as parameters
4. **Execute** Claude Code CLI via `coder ssh` command
5. **Claude Code**:
   - Reads event context from workspace environment
   - Generates Ansible playbook using AI
   - Runs ansible-lint for validation
   - Commits to git with descriptive message
   - Pushes to remote repository
6. **Verify** playbook exists and was pushed
7. **Cleanup** workspace (if configured)

## Prerequisites

### Required Software

| Component | Version | Purpose | Installation Link |
|-----------|---------|---------|------------------|
| **Coder** | v2.0.0+ | Cloud development environments | [coder.com/docs/install](https://coder.com/docs/install) |
| **Coder CLI** | v2.0.0+ | Command-line interface for Coder | [coder.com/docs/cli](https://coder.com/docs/cli) |
| **Claude Code CLI** | Latest | AI coding assistant | [claude.ai/code](https://claude.ai/code) |
| **Ansible Core** | 2.16+ | Automation engine | [docs.ansible.com](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) |
| **Git** | 2.x+ | Version control | [git-scm.com](https://git-scm.com/) |

### Coder Deployment

You need a **running Coder instance**. Options:

1. **Self-hosted**: Deploy Coder on your infrastructure
   - Docker/Podman: `docker run -it --rm -p 3000:3000 ghcr.io/coder/coder:latest`
   - Kubernetes: Use Coder Helm chart
   - See: https://coder.com/docs/install

2. **Cloud-hosted**: Use Coder's managed service (coder.com)

### Claude Code Authentication

Claude Code CLI requires authentication. Options:

1. **Session token**: Login via `claude auth login` (interactive)
2. **API key**: Set `ANTHROPIC_API_KEY` environment variable
3. **Pre-authenticated workspace**: Include auth in Coder template

**Note**: For automated workflows (headless mode), you must pre-configure authentication in the Coder workspace template.

### Git Repository

- Git repository with SSH or HTTPS access
- Git credentials configured for pushing (PAT, SSH key, or deploy token)
- Repository should have `playbooks/` directory structure

### Ansible Collections

Required collections (installed in Coder workspace):

- `ansible.eda` - Event-driven automation
- `ansible.mcp` - MCP client for AAP
- `ansible.controller` - AAP controller interaction, job launching

## Setup

### 1. Coder Installation

#### Install Coder Server

**Option A: Docker (Quick Start)**

```bash
# Run Coder server
docker run -it --rm \
  -p 3000:3000 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  ghcr.io/coder/coder:latest

# Access Coder UI at http://localhost:3000
# Create admin user when prompted
```

**Option B: Kubernetes (Production)**

```bash
# Add Coder Helm repository
helm repo add coder-v2 https://helm.coder.com/v2

# Install Coder
helm install coder coder-v2/coder \
  --namespace coder \
  --create-namespace \
  --set coder.env[0].name=CODER_ACCESS_URL \
  --set coder.env[0].value=https://coder.example.com
```

**Option C: Binary Installation**

```bash
# Download Coder binary
curl -fsSL https://coder.com/install.sh | sh

# Start Coder server
coder server --access-url http://localhost:3000
```

See official documentation: https://coder.com/docs/install

#### Install Coder CLI

**On the AAP EDA controller or Ansible control node:**

```bash
# Linux/macOS
curl -fsSL https://coder.com/install.sh | sh

# Verify installation
coder version

# Login to Coder instance
coder login https://coder.example.com
# Follow prompts to authenticate
```

**Verify CLI access:**

```bash
# Test CLI connectivity
coder list

# Should show: "No workspaces found" (if none created yet)
```

### 2. Coder Template Configuration

Coder uses **templates** to define workspace environments. You need to create a template for Ansible AIOps playbook generation.

#### Create Template Directory

```bash
mkdir -p ~/coder-templates/ansible-remediation
cd ~/coder-templates/ansible-remediation
```

#### Create `main.tf` (Terraform Template)

**File: `~/coder-templates/ansible-remediation/main.tf`**

```hcl
terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 0.12"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

# Coder provider configuration
provider "coder" {}

# Docker provider (or use kubernetes provider for k8s deployments)
provider "docker" {}

# Event context parameters (passed from Ansible playbook)
variable "event_type" {
  description = "Type of event triggering remediation"
  default     = "unknown"
  type        = string
}

variable "event_description" {
  description = "Detailed description of the event"
  default     = ""
  type        = string
}

variable "event_host" {
  description = "Target host for remediation"
  default     = ""
  type        = string
}

variable "event_severity" {
  description = "Event severity level"
  default     = "medium"
  type        = string
}

variable "event_service" {
  description = "Service affected by the event"
  default     = ""
  type        = string
}

variable "event_tags" {
  description = "Comma-separated event tags"
  default     = ""
  type        = string
}

variable "git_remote_url" {
  description = "Git repository URL for pushing generated playbooks"
  default     = ""
  type        = string
  sensitive   = true
}

# Coder agent for workspace access
resource "coder_agent" "main" {
  arch           = "amd64"
  os             = "linux"
  startup_script = <<-EOT
    #!/bin/bash
    set -e

    # Write event context to file for Claude Code
    cat > /home/coder/event-context.md <<EOF
    # Event Context for Remediation

    - **Event Type**: ${var.event_type}
    - **Description**: ${var.event_description}
    - **Target Host**: ${var.event_host}
    - **Severity**: ${var.event_severity}
    - **Service**: ${var.event_service}
    - **Tags**: ${var.event_tags}

    ## Task

    Create an Ansible playbook to remediate this issue.
    Save to: playbooks/${var.event_type}_${var.event_host}.yml
    EOF

    # Clone git repository
    if [ -n "${var.git_remote_url}" ]; then
      git clone ${var.git_remote_url} /home/coder/workspace
      cd /home/coder/workspace
    fi

    # Install Ansible collections
    ansible-galaxy collection install -r requirements.yml -f
  EOT

  # Environment variables for Claude Code and Ansible
  env = {
    EVENT_TYPE        = var.event_type
    EVENT_DESCRIPTION = var.event_description
    EVENT_HOST        = var.event_host
    EVENT_SEVERITY    = var.event_severity
    GIT_REMOTE_URL    = var.git_remote_url
  }
}

# Docker container for workspace
resource "docker_image" "ansible" {
  name = "ansible-aiops-workspace:latest"
  build {
    context = "${path.module}"
    tag     = ["ansible-aiops-workspace:latest"]
  }
}

resource "docker_container" "workspace" {
  image = docker_image.ansible.image_id
  name  = "coder-${data.coder_workspace.me.id}"

  # Coder agent
  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
  ]

  # Workspace lifecycle
  command = ["sh", "-c", coder_agent.main.init_script]
}

# Workspace metadata
data "coder_workspace" "me" {}
```

#### Create Dockerfile

**File: `~/coder-templates/ansible-remediation/Dockerfile`**

```dockerfile
# Base image with Python and system dependencies
FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    openssh-client \
    sshpass \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -s /bin/bash coder && \
    echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Switch to coder user
USER coder
WORKDIR /home/coder

# Install Ansible and required Python packages
RUN pip install --user --no-cache-dir \
    ansible-core>=2.16 \
    ansible-lint \
    jmespath \
    requests

# Install Claude Code CLI
# NOTE: This assumes Claude Code CLI is available via curl/install script
# Adjust based on actual Claude Code installation method
# For now, this is a placeholder - you must configure actual installation
RUN curl -fsSL https://example.com/install-claude-code.sh | sh || \
    echo "WARNING: Claude Code CLI installation placeholder - configure actual installation"

# Configure git
RUN git config --global user.name "AIOps Bot" && \
    git config --global user.email "aiops@example.com"

# Set environment variables
ENV PATH="/home/coder/.local/bin:${PATH}"
ENV ANSIBLE_HOST_KEY_CHECKING=False
ENV ANSIBLE_LOCALHOST_WARNING=False

# Default command
CMD ["/bin/bash"]
```

**IMPORTANT**: The Claude Code CLI installation in the Dockerfile is a **placeholder**. You must:

1. Obtain the actual Claude Code CLI binary or installation method from Anthropic
2. Ensure it's properly authenticated (via API key or session token)
3. Update the Dockerfile accordingly

#### Create Template Requirements

**File: `~/coder-templates/ansible-remediation/requirements.yml`**

```yaml
---
collections:
  - name: ansible.eda
    version: ">=1.0.0"
  - name: ansible.mcp
    version: ">=1.0.0"
  - name: ansible.controller
    version: ">=4.5.0"
  - name: ansible.utils
    version: ">=2.0.0"
```

#### Push Template to Coder

```bash
# Navigate to template directory
cd ~/coder-templates/ansible-remediation

# Create template in Coder
coder templates create ansible-remediation \
  --directory . \
  --variable event_type="test" \
  --variable event_description="Test event" \
  --variable event_host="localhost" \
  --yes

# Verify template creation
coder templates list
```

### 3. Claude Code Setup

Claude Code must be available and authenticated in the Coder workspace.

#### Option A: Pre-authenticate in Docker Image

**Add to Dockerfile:**

```dockerfile
# Set Claude Code API key (use build arg for security)
ARG ANTHROPIC_API_KEY
ENV ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}

# Verify Claude Code installation
RUN claude --version || echo "Claude Code not installed"
```

**Build with API key:**

```bash
docker build \
  --build-arg ANTHROPIC_API_KEY="sk-ant-..." \
  -t ansible-aiops-workspace:latest \
  .
```

#### Option B: Configure in Coder Template

**Add to main.tf startup script:**

```hcl
startup_script = <<-EOT
  # Authenticate Claude Code
  export ANTHROPIC_API_KEY="${var.anthropic_api_key}"
  claude --version
EOT
```

**Add variable to main.tf:**

```hcl
variable "anthropic_api_key" {
  description = "Anthropic API key for Claude Code"
  type        = string
  sensitive   = true
}
```

#### Option C: Use Coder Secrets

```bash
# Create secret in Coder
coder secrets create ANTHROPIC_API_KEY

# Reference in template
env = {
  ANTHROPIC_API_KEY = data.coder_parameter.anthropic_api_key.value
}
```

**Note**: Exact authentication method depends on Claude Code CLI capabilities. Consult Claude Code documentation for the supported authentication methods.

### 4. Environment Configuration

#### Configure Ansible Inventory

**File: `inventory.yml`** (or update existing)

```yaml
---
all:
  hosts:
    localhost:
      ansible_connection: local
  vars:
    # Coder Configuration
    coder_url: "https://coder.example.com"  # Your Coder instance URL
    coder_template_name: "ansible-remediation"
    
    # Git Configuration
    git_remote_url: "https://github.com/your-org/your-repo.git"
    git_token: "{{ lookup('env', 'GIT_TOKEN') }}"
    
    # MCP Configuration (existing)
    mcp_server_url: "{{ lookup('env', 'AAP_MCP_SERVER_URL') }}"
    mcp_bearer_token: "{{ lookup('env', 'AAP_BEARER_TOKEN') }}"
```

#### Set Environment Variables

```bash
# Coder Authentication
export CODER_URL="https://coder.example.com"
export CODER_SESSION_TOKEN="your-coder-session-token"

# Git Credentials
export GIT_TOKEN="ghp_your_github_personal_access_token"
export GIT_USERNAME="aiops-bot"
export GIT_EMAIL="aiops@example.com"

# AAP/MCP (existing)
export AAP_MCP_SERVER_URL="https://aap.example.com:8448"
export AAP_BEARER_TOKEN="your_aap_bearer_token"

# Optional: Claude Code API Key (if not in Docker image)
export ANTHROPIC_API_KEY="sk-ant-api-key-here"
```

**Persistent configuration:**

```bash
# Add to ~/.bashrc or ~/.zshrc
echo 'export CODER_URL="https://coder.example.com"' >> ~/.bashrc
echo 'export CODER_SESSION_TOKEN="..."' >> ~/.bashrc
source ~/.bashrc
```

#### Verify Coder CLI Access

```bash
# Test Coder CLI
coder list

# Test template access
coder templates list | grep ansible-remediation

# Create test workspace
coder create test-workspace --template ansible-remediation --yes

# SSH into test workspace
coder ssh test-workspace -- whoami

# Cleanup test workspace
coder delete test-workspace --yes
```

## Usage

### Running the Workflow

#### From EDA Rulebook

**File: `rulebooks/find-template-on-unmatched-event.yml`**

Update the fallback action to use the Coder workflow:

```yaml
rules:
  - name: Catch-all for unknown events
    condition: event.type is defined
    action:
      run_playbook:
        name: playbooks/intelligent-aiops-workflow-coder.yml
        extra_vars:
          event_type: "{{ event.type }}"
          event_description: "{{ event.payload.description }}"
          event_host: "{{ event.payload.hostname }}"
          event_severity: "{{ event.payload.severity }}"
          event_service: "{{ event.payload.service | default('') }}"
          event_tags: "{{ event.payload.tags | default([]) }}"
```

#### Manual Execution

```bash
# Run workflow with event context
ansible-navigator run playbooks/intelligent-aiops-workflow-coder.yml -m stdout \
  -i inventory.yml \
  -e "event_type=disk_alert" \
  -e "event_description='Disk usage at 95% on /var'" \
  -e "event_host=web-server-01" \
  -e "event_severity=high" \
  -e "event_service=nginx" \
  -e 'event_tags=["web","production"]'
```

#### Test with Minimal Event

```bash
# Simplest test
ansible-navigator run playbooks/intelligent-aiops-workflow-coder.yml -m stdout \
  -e "event_type=test" \
  -e "event_description='Test event for Coder integration'" \
  -e "event_host=localhost" \
  -e "event_severity=low" \
  -e "mcp_server_url=''" \
  -vv
```

### Expected Output

```
TASK [Display event context] ***
ok: [localhost] => 
  msg:
  - ==========================================
  - Unknown Event - Starting AI Workflow (Coder)
  - ==========================================
  - 'Event Type: disk_alert'
  - 'Description: Disk usage at 95% on /var'
  - 'Host: web-server-01'
  - 'Severity: high'
  - 'Service: nginx'
  - ==========================================

TASK [Create Coder workspace from template] ***
changed: [localhost]

TASK [Wait for workspace to be ready] ***
ok: [localhost]

TASK [Display workspace creation result] ***
ok: [localhost] => 
  msg:
  - ✅ Coder Workspace Created
  - 'Workspace: aiops-disk-alert-20260710-143022'
  - 'Status: Running'
  - 'URL: https://coder.example.com/aiops-disk-alert-20260710-143022'

TASK [Execute Claude Code via Coder SSH] ***
changed: [localhost]

TASK [Display Claude Code execution result] ***
ok: [localhost] => 
  msg:
  - 'Claude Code Execution:'
  - 'Created playbook: playbooks/disk_alert_web_server_01.yml'
  - 'Ran ansible-lint: 0 errors'
  - 'Committed to git'
  - 'Pushed to origin/main'

TASK [Workflow Summary] ***
ok: [localhost] => 
  msg:
  - ==========================================
  - ✅ Intelligent AIOps Workflow Complete!
  - ==========================================
  - 'Workflow Path: Coder + Claude Code → Git'
  - 'Generated Playbook: playbooks/disk_alert_web_server_01.yml'
  - 'Coder Workspace: aiops-disk-alert-20260710-143022'
  - 'Git: https://github.com/your-org/your-repo.git'
  - ==========================================
```

## Workflow Details

### Step-by-Step Process

1. **Event Reception**
   - EDA rulebook receives event from source (webhook, Kafka, etc.)
   - Event contains: type, description, hostname, severity, service, tags

2. **MCP Query** (same as original workflow)
   - Query AAP via MCP for matching job templates
   - Score templates based on event attributes
   - If score ≥ 100: Launch AAP job template (skip Coder)

3. **Workspace Creation** (if no MCP match)
   - Generate unique workspace name: `aiops-{event_type}-{timestamp}`
   - Execute: `coder create {workspace_name} --template ansible-remediation`
   - Pass event context as template parameters
   - Wait for workspace status = "Running"

4. **Claude Code Execution**
   - SSH into workspace: `coder ssh {workspace_name}`
   - Execute: `echo "{prompt}" | claude --yes`
   - Claude Code:
     - Reads event context from environment/file
     - Generates Ansible playbook with FQCN, error handling, idempotency
     - Saves to `playbooks/{event_type}_{hostname}.yml`
     - Runs `ansible-lint` for validation
     - Commits to git with descriptive message
     - Pushes to remote repository

5. **Verification**
   - Check if playbook file exists in workspace
   - Retrieve playbook content for logging
   - Verify git push succeeded

6. **Cleanup** (optional)
   - Delete workspace: `coder delete {workspace_name} --yes`
   - Frees resources for next event

### Workspace Lifecycle

| State | Description | Duration |
|-------|-------------|----------|
| **Creating** | Provisioning container, cloning git repo | 30-60s |
| **Running** | Ready for SSH access and Claude Code execution | Variable |
| **Stopping** | Graceful shutdown initiated | 10-20s |
| **Stopped** | Container stopped, resources freed | N/A |
| **Deleting** | Removing workspace and data | 5-10s |

**Auto-cleanup**: Workspaces are deleted after successful playbook generation to save resources. Set `auto_cleanup_workspace: false` to preserve workspaces for debugging.

### Git Workflow

Claude Code performs the following git operations in the workspace:

```bash
# 1. Repository already cloned in workspace startup script
cd /home/coder/workspace

# 2. Create playbook
# (performed by Claude Code)

# 3. Run validation
ansible-lint playbooks/disk_alert_web_server_01.yml

# 4. Git operations (performed by Claude Code)
git add playbooks/disk_alert_web_server_01.yml
git commit -m "AI-generated playbook for disk_alert on web-server-01" \
  -m "Event: disk_alert" \
  -m "Severity: high" \
  -m "Generated by Claude Code via Coder workspace"
git push origin main
```

## Troubleshooting

### Coder CLI Issues

**Problem**: `coder: command not found`

**Solution**: Install Coder CLI

```bash
curl -fsSL https://coder.com/install.sh | sh
# Or use package manager
brew install coder  # macOS
```

**Problem**: `Coder CLI is not authenticated`

**Solution**: Login to Coder instance

```bash
coder login https://coder.example.com
# Follow prompts to authenticate
```

**Problem**: `Failed to connect to Coder server`

**Solution**: Check Coder server is running and accessible

```bash
# Check server status
curl -I https://coder.example.com

# Verify CODER_URL environment variable
echo $CODER_URL

# Re-login if needed
coder logout
coder login https://coder.example.com
```

### Workspace Creation Failures

**Problem**: `Template "ansible-remediation" not found`

**Solution**: Verify template exists and is pushed to Coder

```bash
# List templates
coder templates list

# If missing, create template
cd ~/coder-templates/ansible-remediation
coder templates create ansible-remediation --directory . --yes
```

**Problem**: `Workspace creation timeout`

**Solution**: Increase timeout in playbook

```yaml
# In intelligent-aiops-workflow-coder.yml
vars:
  workspace_timeout: 1200  # Increase from 600 to 1200 seconds
```

**Problem**: `Docker image build failed`

**Solution**: Check Dockerfile and build logs

```bash
# Manually build Docker image
cd ~/coder-templates/ansible-remediation
docker build -t ansible-aiops-workspace:latest .

# Check for errors in build output
```

### Claude Code Execution Issues

**Problem**: `claude: command not found` in workspace

**Solution**: Verify Claude Code is installed in Docker image

```bash
# SSH into workspace manually
coder ssh {workspace_name}

# Check if Claude Code CLI exists
which claude
claude --version

# If missing, Claude Code was not installed in Dockerfile
# Update Dockerfile and rebuild template
```

**Problem**: `Authentication failed` for Claude Code

**Solution**: Configure API key in workspace

```bash
# Check if ANTHROPIC_API_KEY is set
coder ssh {workspace_name} -- env | grep ANTHROPIC

# If missing, add to template or use Coder secrets
# See "Claude Code Setup" section
```

**Problem**: `Playbook generation failed` or empty output

**Solution**: Check Claude Code execution logs

```bash
# Run with verbose output
ansible-navigator run playbooks/intelligent-aiops-workflow-coder.yml -m stdout -vvv

# SSH into workspace and test Claude Code manually
coder ssh {workspace_name}
echo "Create a simple Ansible playbook" | claude --yes
```

### Git Integration Issues

**Problem**: `Permission denied (publickey)` when pushing to git

**Solution**: Configure git credentials in workspace

```bash
# For HTTPS with token
git remote set-url origin https://${GIT_TOKEN}@github.com/user/repo.git

# For SSH
# Add SSH key to workspace via Coder template or startup script
```

**Problem**: `Git push failed: authentication required`

**Solution**: Verify GIT_TOKEN environment variable

```bash
# Check token is set
echo $GIT_TOKEN | head -c 10

# Ensure token has repo write permissions
# GitHub: Settings → Developer settings → Personal access tokens
```

### Workspace Cleanup Issues

**Problem**: `Failed to delete workspace: workspace is running`

**Solution**: Stop workspace before deleting

```bash
# Stop workspace first
coder stop {workspace_name}

# Then delete
coder delete {workspace_name} --yes
```

**Problem**: Workspaces accumulating, consuming resources

**Solution**: Enable auto-cleanup or run periodic cleanup

```bash
# Enable in playbook
auto_cleanup_workspace: true

# Or run manual cleanup script
coder list --output json | \
  jq -r '.[] | select(.name | startswith("aiops-")) | .name' | \
  xargs -I {} coder delete {} --yes
```

## Security Considerations

### Credential Management

**Git Tokens**:
- Store in environment variables, not in playbooks or templates
- Use GitHub Personal Access Tokens (PAT) with minimal scope (only `repo` write)
- Rotate tokens regularly
- Consider using deploy keys for specific repositories

**Anthropic API Keys**:
- Never commit API keys to git repositories
- Use Coder secrets or environment variables
- Set appropriate usage limits in Anthropic console

**Coder Authentication**:
- Use session tokens, not passwords, in automation
- Tokens expire; implement refresh mechanism
- Use RBAC in Coder to limit who can create workspaces

### Network Isolation

**Workspace Network Access**:
- Limit outbound connections from workspaces (if using Kubernetes with network policies)
- Only allow access to: Git repository, AAP MCP server, Anthropic API
- Block access to internal services unless explicitly needed

### Audit Logging

Enable audit logging for:

1. **Coder Workspace Activity**:
   - Workspace creation/deletion events
   - SSH session logs
   - Resource usage metrics

2. **Git Operations**:
   - All commits include event context in commit message
   - Use dedicated "AIOps Bot" git user for attribution
   - Enable branch protection (require PR reviews for sensitive branches)

3. **Claude Code Usage**:
   - Log all prompts and generated code
   - Monitor API usage and costs
   - Review generated playbooks before deploying to production

### Generated Code Review

**Do NOT auto-deploy generated playbooks to production**:

1. Generated playbooks should be committed to git
2. Require human review via Pull Request process
3. Run tests (ansible-lint, molecule) in CI/CD
4. Obtain approval before merging to main branch
5. Manually create AAP job template after review

**Review checklist**:
- [ ] Playbook uses FQCN (Fully Qualified Collection Names)
- [ ] Error handling is appropriate (block/rescue)
- [ ] No hardcoded credentials or secrets
- [ ] Idempotency is ensured
- [ ] Target hosts are correct
- [ ] Privilege escalation (become) is justified
- [ ] No destructive operations without confirmation

## Comparison with API-based Approach

### API Approach (Original: `intelligent-aiops-workflow.yml`)

```yaml
# Single API call
- name: Generate playbook with Code Assistant
  ansible.builtin.uri:
    url: "{{ lightspeed_url }}"
    method: POST
    body:
      text: "{{ prompt }}"
  register: response

# Receive generated code
- set_fact:
    playbook_content: "{{ response.json.playbook }}"
```

**Characteristics**:
- ✅ Simple, single HTTP request
- ✅ Fast (typically 10-30 seconds)
- ✅ No infrastructure overhead
- ❌ Limited context (prompt only)
- ❌ No testing/validation before commit
- ❌ Single-file output only
- ❌ No iterative refinement

### Coder + Claude Code Approach (New: `intelligent-aiops-workflow-coder.yml`)

```yaml
# Create isolated workspace
- name: Create Coder workspace
  command: coder create {{ workspace_name }} --template ansible-remediation

# Execute Claude Code with full repository context
- name: Execute Claude Code
  shell: |
    coder ssh {{ workspace_name }} -- claude --yes
```

**Characteristics**:
- ✅ Full repository context (existing playbooks, roles, collections)
- ✅ Built-in testing (ansible-lint, syntax validation)
- ✅ Multi-file generation (playbooks, roles, variables)
- ✅ Isolated execution environment
- ✅ Git integration (automatic commit with attribution)
- ❌ More complex setup (Coder infrastructure required)
- ❌ Slower (60-120 seconds including workspace creation)
- ❌ Higher resource usage (one container per event)

### When to Use Each

| Use Case | Recommended Approach |
|----------|---------------------|
| High event volume (100+ events/hour) | **API** - Lower latency, less resource usage |
| Complex multi-file changes needed | **Coder + Claude Code** - Can generate roles, variables, inventories |
| Need testing before commit | **Coder + Claude Code** - Built-in ansible-lint, syntax checks |
| Limited infrastructure | **API** - No additional services required |
| Require full repository context | **Coder + Claude Code** - Can read existing code patterns |
| Simple single-playbook generation | **API** - Faster, simpler workflow |
| Learning/training organization | **Coder + Claude Code** - Better for human oversight and iteration |
| Production critical incidents | **Coder + Claude Code** - More validation, safer commits |

### Hybrid Approach

You can use **both** workflows based on event severity:

```yaml
# In EDA rulebook
rules:
  - name: High-severity events → Use Coder for thorough generation
    condition: event.severity in ["critical", "high"]
    action:
      run_playbook:
        name: playbooks/intelligent-aiops-workflow-coder.yml

  - name: Low-severity events → Use API for fast generation
    condition: event.severity in ["low", "medium"]
    action:
      run_playbook:
        name: playbooks/intelligent-aiops-workflow.yml
```

## References

- **Coder Documentation**: https://coder.com/docs
- **Coder CLI Reference**: https://coder.com/docs/cli
- **Claude Code**: https://claude.ai/code
- **Ansible AIOps README**: `/home/gmadappa/ansible/ansible-aiops/README.md`
- **Original API Workflow**: `/home/gmadappa/ansible/ansible-aiops/playbooks/intelligent-aiops-workflow.yml`

## Support

For issues or questions:

1. Check Coder logs: `coder logs {workspace_name}`
2. Check workspace status: `coder list`
3. Review Ansible playbook output with `-vvv` verbosity
4. Consult Coder documentation: https://coder.com/docs
5. Review Claude Code CLI usage: `claude --help`
