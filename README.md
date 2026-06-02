# Ansible Sage Demo

Client project that uses Ansible Sage to generate playbooks and push them to Git.

## Setup

1. **Set your Git token as environment variable:**
   ```bash
   export GIT_TOKEN="ghp_your_github_token_here"
   ```

2. **Edit `generate-and-push.yml` and update:**
   - `git_remote_url`: Your Git repository URL
   - `event_type`: Type of event to generate playbook for
   - `event_description`: Event description
   - `target_host`: Target hostname

## Usage

**Run the playbook:**
```bash
ansible-playbook generate-and-push.yml
```

**With custom event (override variables):**
```bash
ansible-playbook generate-and-push.yml \
  -e "event_type=high_cpu" \
  -e "event_description='CPU at 98%'" \
  -e "target_host=app-server-01"
```

**Skip Git push (local only):**
```bash
ansible-playbook generate-and-push.yml --skip-tags git
```

## What It Does

1. Calls Ansible Sage API with event details
2. Receives AI-generated playbook
3. Saves playbook to `generated-playbooks/playbooks/`
4. Commits to local Git
5. Pushes to remote repository

## Output

Generated playbooks are saved in:
```
generated-playbooks/
└── playbooks/
    ├── disk_full_web-server-01_example_com.yml
    ├── high_cpu_app-server-03_prod_example_com.yml
    └── ...
```

## Requirements

- Ansible Sage service running on http://localhost:8000
- Git installed
- GitHub/GitLab Personal Access Token (for push)

## Examples

**Disk full event:**
```bash
ansible-playbook generate-and-push.yml \
  -e "event_type=disk_full" \
  -e "event_description='Disk at 95% on /var/log'" \
  -e "target_host=web01.example.com"
```

**Service down:**
```bash
ansible-playbook generate-and-push.yml \
  -e "event_type=service_down" \
  -e "event_description='Nginx service stopped'" \
  -e "target_host=lb01.example.com"
```

**High CPU:**
```bash
ansible-playbook generate-and-push.yml \
  -e "event_type=high_cpu" \
  -e "event_description='CPU usage at 98%'" \
  -e "target_host=app-server-01"
```
