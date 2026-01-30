#!/bin/bash
# RADKit MCP Test Script
# Tests MCP endpoint via HTTP Streamable transport
#
# Usage: ./radkit-mcp-test.sh [OPTIONS]
#   -H, --host HOST     MCP server host (default: 127.0.0.1)
#   -p, --port PORT     MCP server port (default: 8000)
#   -v, --verbose       Show full JSON responses
#   -t, --tool TOOL     Specific tool to test (default: get_device_inventory_names_tool)
#   -h, --help          Show this help

set -e

# Default Configuration
MCP_HOST="127.0.0.1"
MCP_PORT="8000"
VERBOSE=false
TEST_TOOL="get_device_inventory_names_tool"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

print_header() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN} $1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

show_help() {
    head -12 "$0" | tail -9
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -H|--host)
            MCP_HOST="$2"
            shift 2
            ;;
        -p|--port)
            MCP_PORT="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -t|--tool)
            TEST_TOOL="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

MCP_URL="http://${MCP_HOST}:${MCP_PORT}/mcp"

print_header "RADKit MCP Test Suite"
print_info "Target: ${MCP_URL}"

# Check if jq is available
if ! command -v jq &> /dev/null; then
    print_warning "jq not found - JSON output will not be formatted"
    JQ_CMD="cat"
else
    JQ_CMD="jq"
fi

# Function to make MCP request
mcp_request() {
    local method="$1"
    local params="$2"
    local id="$3"
    local session_header=""

    if [[ -n "$SESSION_ID" ]]; then
        session_header="-H \"mcp-session-id: ${SESSION_ID}\""
    fi

    local payload=$(cat <<EOF
{
    "jsonrpc": "2.0",
    "id": ${id},
    "method": "${method}",
    "params": ${params}
}
EOF
)

    if [[ "$VERBOSE" == true ]]; then
        print_info "Request payload:"
        echo "$payload" | $JQ_CMD 2>/dev/null || echo "$payload"
    fi

    local response
    if [[ -n "$SESSION_ID" ]]; then
        response=$(curl -sS -X POST "${MCP_URL}" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json, text/event-stream" \
            -H "mcp-session-id: ${SESSION_ID}" \
            -d "$payload" 2>&1)
    else
        response=$(curl -sS -X POST "${MCP_URL}" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json, text/event-stream" \
            -d "$payload" 2>&1)
    fi

    echo "$response"
}

# Function to extract JSON from SSE response
extract_json() {
    local response="$1"
    # Handle SSE format (data: {...}) or plain JSON
    if echo "$response" | grep -q "^data:"; then
        echo "$response" | grep "^data:" | sed 's/^data: //' | head -1
    else
        echo "$response"
    fi
}

#######################################
# Test 1: Initialize MCP Session
#######################################
print_header "Test 1: Initialize MCP Session"

# MCP protocol requires: initialize -> wait for response -> send initialized notification
# Use curl with headers to capture session ID

INIT_PAYLOAD=$(cat <<EOF
{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
        "protocolVersion": "2024-11-05",
        "capabilities": {},
        "clientInfo": {
            "name": "radkit-mcp-test",
            "version": "1.0.0"
        }
    }
}
EOF
)

# Send initialize request and capture both headers and body
INIT_FULL=$(curl -sS -i -X POST "${MCP_URL}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d "$INIT_PAYLOAD" 2>&1)

# Extract session ID from response headers
SESSION_ID=$(echo "$INIT_FULL" | grep -i "mcp-session-id:" | head -1 | awk '{print $2}' | tr -d '\r\n')

# Extract the JSON body (everything after the blank line)
INIT_BODY=$(echo "$INIT_FULL" | sed -n '/^\r*$/,$p' | tail -n +2)

if [[ -n "$SESSION_ID" ]]; then
    print_status "Session initialized"
    print_info "Session ID: ${SESSION_ID}"

    if [[ "$VERBOSE" == true ]]; then
        print_info "Initialize response:"
        echo "$INIT_BODY" | $JQ_CMD 2>/dev/null || echo "$INIT_BODY"
    fi

    # Send initialized notification (required by MCP protocol)
    print_info "Sending initialized notification..."
    NOTIF_PAYLOAD=$(cat <<EOF
{
    "jsonrpc": "2.0",
    "method": "notifications/initialized",
    "params": {}
}
EOF
)

    curl -sS -X POST "${MCP_URL}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -H "mcp-session-id: ${SESSION_ID}" \
        -d "$NOTIF_PAYLOAD" >/dev/null 2>&1

    # Give the server a moment to process
    sleep 1
    print_status "Initialization complete"
else
    print_error "Failed to get session ID"
    print_info "Response:"
    echo "$INIT_FULL" | head -20
    exit 1
fi

#######################################
# Test 2: List Available Tools
#######################################
print_header "Test 2: List Available Tools"

TOOLS_RESPONSE=$(mcp_request "tools/list" '{}' 2)
TOOLS_JSON=$(extract_json "$TOOLS_RESPONSE")

if echo "$TOOLS_JSON" | grep -q '"tools"'; then
    print_status "Tools list retrieved"

    if [[ "$VERBOSE" == true ]]; then
        echo "$TOOLS_JSON" | $JQ_CMD 2>/dev/null || echo "$TOOLS_JSON"
    else
        # Extract and display tool names
        TOOL_NAMES=$(echo "$TOOLS_JSON" | $JQ_CMD -r '.result.tools[].name' 2>/dev/null || echo "")
        if [[ -n "$TOOL_NAMES" ]]; then
            print_info "Available tools:"
            echo "$TOOL_NAMES" | while read -r tool; do
                echo "  - $tool"
            done
        fi
    fi
elif echo "$TOOLS_JSON" | grep -q '"error"'; then
    print_error "Failed to list tools"
    echo "$TOOLS_JSON" | $JQ_CMD '.error' 2>/dev/null || echo "$TOOLS_JSON"
else
    print_warning "Unexpected response:"
    echo "$TOOLS_RESPONSE" | head -10
fi

#######################################
# Test 3: Call Test Tool
#######################################
print_header "Test 3: Call Tool - ${TEST_TOOL}"

TOOL_RESPONSE=$(mcp_request "tools/call" "{
    \"name\": \"${TEST_TOOL}\",
    \"arguments\": {}
}" 3)

TOOL_JSON=$(extract_json "$TOOL_RESPONSE")

if echo "$TOOL_JSON" | grep -q '"result"'; then
    print_status "Tool executed successfully"

    if [[ "$VERBOSE" == true ]]; then
        echo "$TOOL_JSON" | $JQ_CMD 2>/dev/null || echo "$TOOL_JSON"
    else
        # Try to extract content
        CONTENT=$(echo "$TOOL_JSON" | $JQ_CMD -r '.result.content[0].text' 2>/dev/null || echo "")
        if [[ -n "$CONTENT" && "$CONTENT" != "null" ]]; then
            print_info "Result:"
            echo "$CONTENT" | $JQ_CMD 2>/dev/null || echo "$CONTENT"
        else
            echo "$TOOL_JSON" | $JQ_CMD '.result' 2>/dev/null || echo "$TOOL_JSON"
        fi
    fi
elif echo "$TOOL_JSON" | grep -q '"error"'; then
    print_error "Tool execution failed"
    echo "$TOOL_JSON" | $JQ_CMD '.error' 2>/dev/null || echo "$TOOL_JSON"
else
    print_warning "Unexpected response:"
    echo "$TOOL_RESPONSE" | head -20
fi

#######################################
# Summary
#######################################
print_header "Test Summary"
echo ""
print_info "MCP Endpoint: ${MCP_URL}"
print_info "Session ID: ${SESSION_ID:-N/A}"
print_info "Tool Tested: ${TEST_TOOL}"
echo ""
print_status "Test suite completed"
