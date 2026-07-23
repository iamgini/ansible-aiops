#!/bin/bash
# Test script for MCP integration with AAP

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Testing MCP Integration with AAP ===${NC}\n"

# Check required environment variables
echo "1. Checking environment variables..."
if [[ -z "$AAP_MCP_SERVER_URL" ]]; then
    echo -e "${RED}ERROR: AAP_MCP_SERVER_URL not set${NC}"
    echo "Run: export AAP_MCP_SERVER_URL='https://aap.example.com:8448'"
    exit 1
fi

if [[ -z "$AAP_BEARER_TOKEN" ]]; then
    echo -e "${RED}ERROR: AAP_BEARER_TOKEN not set${NC}"
    echo "Run: export AAP_BEARER_TOKEN='your_token_here'"
    exit 1
fi

echo -e "${GREEN}✓ Environment variables set${NC}\n"

# Check required collections
echo "2. Checking Ansible collections..."
if ! ansible-galaxy collection list | grep -q "ansible.mcp"; then
    echo -e "${YELLOW}WARNING: ansible.mcp collection not found${NC}"
    echo "Installing collections..."
    ansible-galaxy collection install -r requirements.yml
else
    echo -e "${GREEN}✓ Required collections installed${NC}\n"
fi

# Test MCP server connectivity
echo "3. Testing MCP server connectivity..."
ansible localhost -m ansible.mcp.tools_info \
    -a "server_url=$AAP_MCP_SERVER_URL auth_token=$AAP_BEARER_TOKEN" \
    -e "ansible_python_interpreter=$(which python3)" \
    > /dev/null 2>&1

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✓ MCP server is reachable${NC}\n"
else
    echo -e "${RED}ERROR: Cannot connect to MCP server${NC}"
    echo "Check if MCP server is running at: $AAP_MCP_SERVER_URL"
    exit 1
fi

# Run the playbook with sample event data
echo "4. Testing playbook with sample event..."
echo -e "${YELLOW}Running: intelligent-aiops-workflow.yml (uses internal.aiops.aiops_mcp_matcher role)${NC}\n"

ansible-navigator run playbooks/intelligent-aiops-workflow.yml -m stdout \
    -e "event_type=disk_alert" \
    -e "event_description='Disk usage at 95%'" \
    -e "event_service=nginx" \
    -e "event_host=web-server-01" \
    -e "event_severity=high" \
    -e 'event_tags=["web","production","disk"]' \
    -v

if [[ $? -eq 0 ]]; then
    echo -e "\n${GREEN}✓ Playbook executed successfully${NC}\n"
else
    echo -e "\n${RED}ERROR: Playbook execution failed${NC}"
    exit 1
fi

# Summary
echo -e "${GREEN}=== All tests passed! ===${NC}"
echo ""
echo "Next steps:"
echo "1. Review the matched job templates above"
echo "2. Test with EDA: ansible-rulebook --rulebook rulebooks/find-template-on-unmatched-event.yml"
echo "3. Send test event via Event Stream: curl -sk -X POST \${EDA_EVENT_STREAM_URL} -u \${EDA_BASIC_AUTH} -H 'Content-Type: application/json' -d '{\"type\":\"test\",\"payload\":{}}'"
echo ""
