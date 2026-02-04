#!/bin/bash
# fix_scripts.sh - Updates RADKit & MCP server scripts from GitHub
#
# This applies some script updates and other fixes not in the 29-jan-2026 lab image.
# This script trues the image up to the lastest 2-feb-2026 image.
#
# Run as: sudo bash fix_scripts.sh
#
# This script:
# 1. Applies system fixes (Docker DNS, python image, tmpfiles, restart policy)
# 2. Configures R3 router loopback interface
# 3. Downloads and deploys latest scripts from GitHub
#
# v1.0 - 2-Feb-2026

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
}

# Configuration
SCRIPTS_DIR="/home/cisco/scripts/mcp"
MCP_SERVER_DIR="/home/cisco/radkit-mcp-server-community"
BACKUP_SUFFIX=".bak.$(date +%Y%m%d%H%M%S)"

# GitHub Configuration
GITHUB_REPO="ciscomanagedservices/ciscolive26_cw_ai_agents"
GITHUB_BRANCH="main"
GITHUB_PATH="scripts/mcp-server"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/${GITHUB_PATH}"

# Router configuration
R3_HOST="198.18.1.103"
R3_USER="cisco"
R3_PASS="cisco"

# Scripts to download
SCRIPTS=(
    "setup_mcp.sh"
    "radkit-mcp-test.sh"
    "radkit-install.sh"
    "recover_radkit.sh"
    "enroll_client.py"
)

#######################################
# Check Prerequisites
#######################################
check_prerequisites() {
    print_header "Checking Prerequisites"

    # Must run as root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
    print_status "Running as root"

    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        exit 1
    fi
    print_status "Docker available"

    # Check curl
    if ! command -v curl &> /dev/null; then
        print_error "curl is not installed"
        exit 1
    fi
    print_status "curl available"

    # Check sshpass for router config
    if ! command -v sshpass &> /dev/null; then
        print_warning "sshpass not found - installing..."
        apt-get update -qq && apt-get install -y -qq sshpass
        print_status "sshpass installed"
    else
        print_status "sshpass available"
    fi

    # Check network connectivity to GitHub
    if ! curl -sS --connect-timeout 5 "https://github.com" >/dev/null 2>&1; then
        print_error "Cannot reach GitHub - check network connectivity"
        exit 1
    fi
    print_status "GitHub reachable"
}

#######################################
# Apply System Fixes
#######################################
apply_system_fixes() {
    print_header "Applying System Fixes"

    # 1. Docker DNS configuration
    if [ ! -f /etc/docker/daemon.json ]; then
        print_status "Configuring Docker DNS..."
        mkdir -p /etc/docker
        tee /etc/docker/daemon.json > /dev/null <<'DOCKERDNS'
{
  "dns": ["8.8.8.8", "8.8.4.4"]
}
DOCKERDNS
        systemctl restart docker
        sleep 3
        print_status "Docker DNS configured and restarted"
    else
        print_status "Docker daemon.json already exists"
    fi

    # 2. Pull python:3.11-slim image
    if ! docker images | grep -q "python.*3.11-slim"; then
        print_status "Pulling python:3.11-slim image..."
        docker pull python:3.11-slim
        print_status "Python image pulled"
    else
        print_status "Python 3.11-slim image already present"
    fi

    # 3. tmpfiles exclusion for /tmp/radkit
    if [ ! -f /etc/tmpfiles.d/radkit.conf ]; then
        print_status "Creating tmpfiles exclusion rule..."
        echo 'x /tmp/radkit' > /etc/tmpfiles.d/radkit.conf
        print_status "Exclusion rule created - /tmp/radkit will persist across reboots"
    else
        print_status "tmpfiles exclusion already exists"
    fi

    # 4. Ensure /tmp/radkit directory exists
    mkdir -p /tmp/radkit
    print_status "/tmp/radkit directory ready"

    # 5. Update radkit-service restart policy (if container exists)
    if docker ps -a --format '{{.Names}}' | grep -q "^radkit-service$"; then
        docker update --restart=unless-stopped radkit-service 2>/dev/null || true
        print_status "radkit-service restart policy set to unless-stopped"

        # Start if not running
        if ! docker ps --format '{{.Names}}' | grep -q "^radkit-service$"; then
            docker start radkit-service 2>/dev/null || true
            print_status "radkit-service container started"
        fi
    else
        print_warning "radkit-service container not found (will be created by radkit-install.sh)"
    fi
}

#######################################
# Configure R3 Router
#######################################
configure_router() {
    print_header "Configuring R3 Router (${R3_HOST})"

    print_status "Configuring Loopback0 interface with 203.0.113.99/24..."

    sshpass -p "${R3_PASS}" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${R3_USER}@${R3_HOST}" << 'ROUTER_EOF'
configure terminal
interface Loopback0
ip address 203.0.113.99 255.255.255.0
no shutdown
end
write memory
ROUTER_EOF

    if [ $? -eq 0 ]; then
        print_status "R3 Loopback0 configured successfully"
    else
        print_warning "Could not configure R3 - router may be unreachable"
    fi
}

#######################################
# Create Directories
#######################################
create_directories() {
    print_header "Creating Directories"

    mkdir -p "${SCRIPTS_DIR}"
    print_status "Created ${SCRIPTS_DIR}"

    if [ ! -d "${MCP_SERVER_DIR}" ]; then
        print_warning "${MCP_SERVER_DIR} does not exist"
        print_warning "You may need to clone the radkit-mcp-server-community repository"
    else
        print_status "${MCP_SERVER_DIR} exists"
    fi
}

#######################################
# Backup Existing Scripts
#######################################
backup_scripts() {
    print_header "Backing Up Existing Scripts"

    for script in "${SCRIPTS[@]}"; do
        if [ -f "${SCRIPTS_DIR}/${script}" ]; then
            cp "${SCRIPTS_DIR}/${script}" "${SCRIPTS_DIR}/${script}${BACKUP_SUFFIX}"
            print_status "Backed up ${script}"
        fi
    done

    # Also backup from MCP server dir
    for script in setup_mcp.sh enroll_client.py; do
        if [ -f "${MCP_SERVER_DIR}/${script}" ]; then
            cp "${MCP_SERVER_DIR}/${script}" "${MCP_SERVER_DIR}/${script}${BACKUP_SUFFIX}"
            print_status "Backed up ${MCP_SERVER_DIR}/${script}"
        fi
    done
}

#######################################
# Download Scripts from GitHub
#######################################
download_scripts() {
    print_header "Downloading Scripts from GitHub"

    echo "Repository: ${GITHUB_REPO}"
    echo "Branch: ${GITHUB_BRANCH}"
    echo "Path: ${GITHUB_PATH}"
    echo ""

    for script in "${SCRIPTS[@]}"; do
        local url="${GITHUB_RAW_BASE}/${script}"
        local dest="${SCRIPTS_DIR}/${script}"

        echo "Downloading ${script}..."
        if curl -sS -f -o "${dest}" "${url}"; then
            print_status "Downloaded ${script}"
        else
            print_error "Failed to download ${script} from ${url}"
            echo "Check that the file exists in the repository"
            exit 1
        fi
    done
}

#######################################
# Copy Scripts to Project Directory
#######################################
copy_to_project() {
    print_header "Copying Scripts to Project Directory"

    if [ -d "${MCP_SERVER_DIR}" ]; then
        cp "${SCRIPTS_DIR}/setup_mcp.sh" "${MCP_SERVER_DIR}/"
        cp "${SCRIPTS_DIR}/enroll_client.py" "${MCP_SERVER_DIR}/"
        print_status "Copied setup_mcp.sh and enroll_client.py to ${MCP_SERVER_DIR}"
    else
        print_warning "${MCP_SERVER_DIR} does not exist - skipping copy"
        print_warning "Scripts are available in ${SCRIPTS_DIR}"
    fi
}

#######################################
# Set Permissions
#######################################
set_permissions() {
    print_header "Setting Permissions"

    chmod +x "${SCRIPTS_DIR}"/*.sh
    chmod +x "${SCRIPTS_DIR}/enroll_client.py"
    print_status "Set execute permissions on scripts in ${SCRIPTS_DIR}"

    if [ -d "${MCP_SERVER_DIR}" ]; then
        chmod +x "${MCP_SERVER_DIR}/setup_mcp.sh" 2>/dev/null || true
        chmod +x "${MCP_SERVER_DIR}/enroll_client.py" 2>/dev/null || true
        print_status "Set execute permissions on scripts in ${MCP_SERVER_DIR}"
    fi
}

#######################################
# Print Summary
#######################################
print_summary() {
    print_header "Update Complete!"

    echo ""
    echo "Scripts downloaded from GitHub and deployed to:"
    echo "  ${SCRIPTS_DIR}/"
    for script in "${SCRIPTS[@]}"; do
        echo "    - ${script}"
    done
    echo ""

    if [ -d "${MCP_SERVER_DIR}" ]; then
        echo "  ${MCP_SERVER_DIR}/"
        echo "    - setup_mcp.sh"
        echo "    - enroll_client.py"
        echo ""
    fi

    echo "System fixes applied:"
    echo "  - Docker DNS configured"
    echo "  - python:3.11-slim image pulled"
    echo "  - tmpfiles exclusion for /tmp/radkit"
    echo "  - radkit-service restart policy set"
    echo "  - R3 Loopback0 configured (203.0.113.99/24)"
    echo ""
    echo "Next steps:"
    echo "  cd ${MCP_SERVER_DIR}"
    echo "  ./setup_mcp.sh"
    echo ""
}

#######################################
# Main
#######################################
main() {
    echo ""
    echo "========================================"
    echo "RADKit MCP Scripts Update (GitHub)"
    echo "========================================"
    echo ""

    check_prerequisites
    apply_system_fixes
    configure_router
    create_directories
    backup_scripts
    download_scripts
    copy_to_project
    set_permissions
    print_summary
}

main
