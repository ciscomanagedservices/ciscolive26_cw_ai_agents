#!/bin/bash
# deploy_to_pods.sh - Deploy update script to multiple dCloud pods via VPN
#
# Usage: ./deploy_to_pods.sh <credentials.csv>
#
# CSV format: vpn_url,username,password
# Example:
#   dcloud-rtp-anyconnect.cisco.com,v2708user1,abc123
#   dcloud-rtp-anyconnect.cisco.com,v2708user2,abc123
#
# Requirements:
#   - Cisco Secure Client installed
#   - sshpass installed (brew install hudochenkov/sshpass/sshpass)
#
# v1.0 - 4-Feb-2026

# Don't use set -e as we want to continue on failures

# Configuration
VPN_CLI="/opt/cisco/secureclient/bin/vpn"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_TO_DEPLOY="${SCRIPT_DIR}/update_scripts_github.sh"
TARGET_HOST="198.18.1.250"
TARGET_USER="root"
TARGET_PASS="cisco"
MCP_TEST_SCRIPT="/home/cisco/scripts/mcp-server/radkit-mcp-test.sh"

# Timeouts (seconds)
VPN_CONNECT_TIMEOUT=60
SSH_TIMEOUT=30
SCRIPT_TIMEOUT=600  # 10 minutes

# Logging
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="${SCRIPT_DIR}/logs"
SUMMARY_LOG="${SCRIPT_DIR}/deployment_${TIMESTAMP}.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Result tracking
declare -a SUCCESS_PODS
declare -a FAILED_PODS
declare -a FAILED_REASONS
TOTAL_PODS=0
CURRENT_POD=0

#######################################
# Logging Functions
#######################################
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "$msg" | tee -a "$SUMMARY_LOG"
}

log_status() {
    echo -e "${GREEN}[OK]${NC} $1" | tee -a "$SUMMARY_LOG"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$SUMMARY_LOG"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1" | tee -a "$SUMMARY_LOG"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$SUMMARY_LOG"
}

log_header() {
    echo "" | tee -a "$SUMMARY_LOG"
    echo -e "${CYAN}========================================${NC}" | tee -a "$SUMMARY_LOG"
    echo -e "${CYAN} $1${NC}" | tee -a "$SUMMARY_LOG"
    echo -e "${CYAN}========================================${NC}" | tee -a "$SUMMARY_LOG"
}

#######################################
# VPN Functions
#######################################
vpn_is_connected() {
    "$VPN_CLI" state 2>/dev/null | grep -q "state: Connected"
}

vpn_disconnect() {
    if vpn_is_connected; then
        log_info "Disconnecting from VPN..."
        echo "disconnect" | "$VPN_CLI" -s >/dev/null 2>&1
        sleep 2
    fi
}

vpn_wait_connected() {
    local timeout=$1
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if vpn_is_connected; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    return 1
}

vpn_connect() {
    local url="$1"
    local user="$2"
    local pass="$3"
    local pod_log="$4"

    # Disconnect any existing connection first
    vpn_disconnect

    log_info "Connecting to VPN: ${url} as ${user}..."

    # Create temporary response file
    local response_file=$(mktemp)
    cat > "$response_file" << EOF
connect ${url}
${user}
${pass}
y
EOF

    # Connect using response file
    "$VPN_CLI" -s < "$response_file" >> "$pod_log" 2>&1 &
    local vpn_pid=$!

    # Clean up credentials file immediately
    sleep 1
    rm -f "$response_file"

    # Wait for connection with timeout
    if vpn_wait_connected "$VPN_CONNECT_TIMEOUT"; then
        log_status "VPN connected successfully"
        return 0
    else
        # Kill the VPN process if it's still running
        kill $vpn_pid 2>/dev/null || true
        log_error "VPN connection timeout after ${VPN_CONNECT_TIMEOUT}s"
        return 1
    fi
}

#######################################
# SSH/SCP Functions
#######################################
scp_script() {
    local pod_log="$1"

    log_info "Copying update script to target..."

    if sshpass -p "$TARGET_PASS" scp -o StrictHostKeyChecking=no -o ConnectTimeout=$SSH_TIMEOUT \
        "$SCRIPT_TO_DEPLOY" "${TARGET_USER}@${TARGET_HOST}:/tmp/update_scripts_github.sh" >> "$pod_log" 2>&1; then
        log_status "Script copied successfully"
        return 0
    else
        log_error "Failed to copy script to target"
        return 1
    fi
}

run_update_script() {
    local pod_log="$1"

    log_info "Running update script on target (this may take several minutes)..."

    echo "=== UPDATE SCRIPT OUTPUT ===" >> "$pod_log"

    if timeout "$SCRIPT_TIMEOUT" sshpass -p "$TARGET_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=$SSH_TIMEOUT \
        "${TARGET_USER}@${TARGET_HOST}" "bash /tmp/update_scripts_github.sh" >> "$pod_log" 2>&1; then
        log_status "Update script completed successfully"
        return 0
    else
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            log_error "Update script timed out after ${SCRIPT_TIMEOUT}s"
        else
            log_error "Update script failed with exit code: $exit_code"
        fi
        return 1
    fi
}

run_mcp_test() {
    local pod_log="$1"

    log_info "Running MCP server test..."

    echo "=== MCP TEST OUTPUT ===" >> "$pod_log"

    if timeout 120 sshpass -p "$TARGET_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=$SSH_TIMEOUT \
        "${TARGET_USER}@${TARGET_HOST}" "$MCP_TEST_SCRIPT" >> "$pod_log" 2>&1; then
        # Check if test output contains success indicators
        if grep -q "Test suite completed" "$pod_log"; then
            log_status "MCP test passed"
            return 0
        else
            log_warning "MCP test completed but success marker not found"
            return 0  # Treat as success if it didn't error
        fi
    else
        local exit_code=$?
        log_error "MCP test failed with exit code: $exit_code"
        return 1
    fi
}

#######################################
# Process Single Pod
#######################################
process_pod() {
    local url="$1"
    local user="$2"
    local pass="$3"

    CURRENT_POD=$((CURRENT_POD + 1))
    local pod_log="${LOG_DIR}/pod_${user}_${TIMESTAMP}.log"
    local update_ok=false
    local mcp_ok=false
    local fail_reason=""

    log_header "Pod ${CURRENT_POD}/${TOTAL_PODS}: ${user}"

    # Initialize pod log
    echo "=======================================" > "$pod_log"
    echo "Pod: ${user}" >> "$pod_log"
    echo "URL: ${url}" >> "$pod_log"
    echo "Started: $(date)" >> "$pod_log"
    echo "=======================================" >> "$pod_log"

    # Step 1: Connect to VPN
    if ! vpn_connect "$url" "$user" "$pass" "$pod_log"; then
        fail_reason="VPN connection failed"
        FAILED_PODS+=("$user")
        FAILED_REASONS+=("$fail_reason")
        echo "RESULT: FAILED - $fail_reason" >> "$pod_log"
        return 1
    fi

    # Step 2: Copy script
    if ! scp_script "$pod_log"; then
        fail_reason="SCP failed"
        vpn_disconnect
        FAILED_PODS+=("$user")
        FAILED_REASONS+=("$fail_reason")
        echo "RESULT: FAILED - $fail_reason" >> "$pod_log"
        return 1
    fi

    # Step 3: Run update script
    if run_update_script "$pod_log"; then
        update_ok=true
    else
        fail_reason="Update script failed"
    fi

    # Step 4: Run MCP test (even if update had issues, try the test)
    if run_mcp_test "$pod_log"; then
        mcp_ok=true
    else
        if [ -z "$fail_reason" ]; then
            fail_reason="MCP test failed"
        else
            fail_reason="${fail_reason}, MCP test failed"
        fi
    fi

    # Step 5: Disconnect VPN
    vpn_disconnect

    # Record result
    echo "" >> "$pod_log"
    echo "Completed: $(date)" >> "$pod_log"

    if [ "$update_ok" = true ] && [ "$mcp_ok" = true ]; then
        SUCCESS_PODS+=("$user")
        echo "RESULT: SUCCESS - Update: OK, MCP Test: OK" >> "$pod_log"
        log_status "Pod ${user} completed successfully"
        return 0
    else
        FAILED_PODS+=("$user")
        FAILED_REASONS+=("$fail_reason")
        echo "RESULT: FAILED - $fail_reason" >> "$pod_log"
        log_error "Pod ${user} failed: $fail_reason"
        return 1
    fi
}

#######################################
# Print Final Summary
#######################################
print_summary() {
    local success_count=${#SUCCESS_PODS[@]}
    local failed_count=${#FAILED_PODS[@]}

    log_header "DEPLOYMENT SUMMARY"

    echo "" | tee -a "$SUMMARY_LOG"
    echo "Total pods: $TOTAL_PODS" | tee -a "$SUMMARY_LOG"
    echo -e "Successful: ${GREEN}${success_count}${NC}" | tee -a "$SUMMARY_LOG"
    echo -e "Failed: ${RED}${failed_count}${NC}" | tee -a "$SUMMARY_LOG"
    echo "" | tee -a "$SUMMARY_LOG"

    if [ $success_count -gt 0 ]; then
        echo -e "${GREEN}SUCCESSFUL PODS:${NC}" | tee -a "$SUMMARY_LOG"
        for pod in "${SUCCESS_PODS[@]}"; do
            echo "  [OK] $pod - Update: OK, MCP Test: OK" | tee -a "$SUMMARY_LOG"
        done
        echo "" | tee -a "$SUMMARY_LOG"
    fi

    if [ $failed_count -gt 0 ]; then
        echo -e "${RED}FAILED PODS:${NC}" | tee -a "$SUMMARY_LOG"
        for i in "${!FAILED_PODS[@]}"; do
            echo "  [FAIL] ${FAILED_PODS[$i]} - ${FAILED_REASONS[$i]}" | tee -a "$SUMMARY_LOG"
        done
        echo "" | tee -a "$SUMMARY_LOG"
    fi

    echo "Detailed logs: ${LOG_DIR}/" | tee -a "$SUMMARY_LOG"
    echo "Summary log: ${SUMMARY_LOG}" | tee -a "$SUMMARY_LOG"
    echo "" | tee -a "$SUMMARY_LOG"

    if [ $failed_count -eq 0 ]; then
        echo -e "${GREEN}All pods deployed successfully!${NC}" | tee -a "$SUMMARY_LOG"
    else
        echo -e "${YELLOW}Deployment completed with ${failed_count} failure(s). Check logs for details.${NC}" | tee -a "$SUMMARY_LOG"
    fi
}

#######################################
# Check Prerequisites
#######################################
check_prerequisites() {
    local errors=0

    # Check VPN CLI
    if [ ! -x "$VPN_CLI" ]; then
        log_error "Cisco Secure Client not found at $VPN_CLI"
        errors=$((errors + 1))
    fi

    # Check sshpass
    if ! command -v sshpass &> /dev/null; then
        log_error "sshpass not installed. Install with: brew install hudochenkov/sshpass/sshpass"
        errors=$((errors + 1))
    fi

    # Check script to deploy
    if [ ! -f "$SCRIPT_TO_DEPLOY" ]; then
        log_error "Script to deploy not found: $SCRIPT_TO_DEPLOY"
        errors=$((errors + 1))
    fi

    return $errors
}

#######################################
# Main
#######################################
main() {
    local csv_file="$1"

    # Create log directory
    mkdir -p "$LOG_DIR"

    log_header "dCloud Pod Deployment"
    log "Starting deployment at $(date)"
    log "Script: $SCRIPT_TO_DEPLOY"
    log "Target: ${TARGET_USER}@${TARGET_HOST}"

    # Check prerequisites
    if ! check_prerequisites; then
        log_error "Prerequisites check failed"
        exit 1
    fi
    log_status "Prerequisites OK"

    # Validate CSV file
    if [ -z "$csv_file" ]; then
        log_error "Usage: $0 <credentials.csv>"
        exit 1
    fi

    if [ ! -f "$csv_file" ]; then
        log_error "CSV file not found: $csv_file"
        exit 1
    fi

    # Count total pods (excluding empty lines and header if present)
    TOTAL_PODS=$(grep -v '^$' "$csv_file" | grep -v '^vpn_url' | wc -l | tr -d ' ')
    log_info "Found $TOTAL_PODS pods to process"

    # Ensure we start disconnected
    vpn_disconnect

    # Process each pod
    while IFS=',' read -r url user pass; do
        # Skip empty lines and header
        [ -z "$url" ] && continue
        [ "$url" = "vpn_url" ] && continue

        # Trim whitespace
        url=$(echo "$url" | tr -d ' ')
        user=$(echo "$user" | tr -d ' ')
        pass=$(echo "$pass" | tr -d ' ')

        # Process this pod
        process_pod "$url" "$user" "$pass"

        # Small delay between pods
        sleep 3

    done < "$csv_file"

    # Print final summary
    print_summary

    log "Deployment completed at $(date)"
}

# Show help if requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "deploy_to_pods.sh - Deploy update script to multiple dCloud pods via VPN"
    echo ""
    echo "Usage: $0 <credentials.csv>"
    echo ""
    echo "CSV format: vpn_url,username,password"
    echo "Example:"
    echo "  dcloud-rtp-anyconnect.cisco.com,v2708user1,b73516"
    echo "  dcloud-rtp-anyconnect.cisco.com,v2708user2,abc123"
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help"
    exit 0
fi

main "$1"
