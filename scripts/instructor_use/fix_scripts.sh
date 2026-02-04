#!/bin/bash
# update_scripts_github.sh - Updates RADKit & MCP server scripts from GitHub
#
# This applies some script updates and other fixes not in the 29-jan-2026 lab image.
# This script trues the image up to the lastest 2-feb-2026 image. This is just for instructor use. 
# Lab participants should not have to run this.
#
# Run as: sudo bash update_scripts_github.sh
#
# This script:
# 1. Applies system fixes (Docker DNS, python image, tmpfiles, restart policy)
# 2. Configures R3 router loopback interface
# 3. Downloads and deploys latest scripts from GitHub
#
# v1.1 - 4-feb-2026 - fixed git links and added some more robustness
# v1.0 - 2-Feb-2026 - initial release

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
SCRIPTS_DIR="/home/cisco/scripts"
MCP_SERVER_DIR="/home/cisco/radkit-mcp-server-community"
BACKUP_SUFFIX=".bak.$(date +%Y%m%d%H%M%S)"

# GitHub Configuration
GITHUB_REPO="ciscomanagedservices/ciscolive26_cw_ai_agents"
GITHUB_BRANCH="main"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}"

# Router configuration
R3_HOST="198.18.1.103"
R3_USER="cisco"
R3_PASS="cisco"

# Scripts to download - format: "github_path|local_name"
# Downloads ALL scripts from the GitHub repo maintaining directory structure
SCRIPT_MAPPINGS=(
    # Root level
    "scripts/fix_scripts.sh|fix_scripts.sh"
    # mcp-server
    "scripts/mcp-server/setup_mcp.sh|mcp-server/setup_mcp.sh"
    "scripts/mcp-server/radkit-mcp-test.sh|mcp-server/radkit-mcp-test.sh"
    "scripts/mcp-server/enroll_client.py|mcp-server/enroll_client.py"
    # radkit
    "scripts/radkit/radkit-install.sh|radkit/radkit-install.sh"
    "scripts/radkit/radkit_fixes.sh|radkit/radkit_fixes.sh"
    # llm
    "scripts/llm/chat_gpt51.sh|llm/chat_gpt51.sh"
    "scripts/llm/chat_gpt52.sh|llm/chat_gpt52.sh"
    "scripts/llm/check_models.sh|llm/check_models.sh"
    # remote_server
    "scripts/remote_server/README.md|remote_server/README.md"
    "scripts/remote_server/remote_register.py|remote_server/remote_register.py"
    # tools
    "scripts/tools/README.md|tools/README.md"
    "scripts/tools/convert_toolbox_to_openai_tools.py|tools/convert_toolbox_to_openai_tools.py"
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
# Fix Container Naming
#######################################
fix_container_name() {
    print_header "Checking Container Names"

    # Check if 'radkit' container exists but 'radkit-service' doesn't
    # This handles the case where the container was created with the old name
    if docker ps -a --format '{{.Names}}' | grep -q "^radkit$"; then
        if ! docker ps -a --format '{{.Names}}' | grep -q "^radkit-service$"; then
            print_warning "Found container named 'radkit' (old naming)"
            print_status "Renaming container 'radkit' to 'radkit-service'..."
            docker rename radkit radkit-service
            print_status "Container renamed successfully"

            # Update restart policy on renamed container
            docker update --restart=unless-stopped radkit-service 2>/dev/null || true
            print_status "Updated restart policy on radkit-service"

            # Start if not running
            if ! docker ps --format '{{.Names}}' | grep -q "^radkit-service$"; then
                docker start radkit-service 2>/dev/null || true
                print_status "radkit-service container started"
            fi
        else
            print_warning "Both 'radkit' and 'radkit-service' containers exist"
            print_warning "Please resolve manually: docker rm radkit"
        fi
    elif docker ps -a --format '{{.Names}}' | grep -q "^radkit-service$"; then
        print_status "Container 'radkit-service' exists (correct naming)"
    else
        print_warning "No radkit container found (will be created by radkit-install.sh)"
    fi
}

#######################################
# Check and Run Bootstrap if Needed
#######################################
check_bootstrap() {
    print_header "Checking RADKit Bootstrap Status"

    local RADKIT_DATA_DIR="/tmp/radkit"
    local RADKIT_IMAGE="containers.cisco.com/radkit/radkit-service:latest"
    local SUPERADMIN_PASSWORD="0e52nsq5jf7f-bxq8whdi7dnT"
    local NEEDS_BOOTSTRAP=false

    # Ensure data directory exists
    mkdir -p "${RADKIT_DATA_DIR}"

    # Check 1: settings.toml doesn't exist = definitely needs bootstrap
    if [ ! -f "${RADKIT_DATA_DIR}/service/settings.toml" ]; then
        print_warning "settings.toml not found - bootstrap needed"
        NEEDS_BOOTSTRAP=true
    else
        print_status "settings.toml exists"

        # Check 2: Even if settings.toml exists, check if the web UI redirects to /bootstrap
        # This catches partial/incomplete bootstrap situations
        if docker ps --format '{{.Names}}' | grep -q "^radkit-service$"; then
            print_status "Checking if RADKit web UI requires bootstrap..."
            sleep 2  # Give container a moment if just started

            # Check if the web endpoint redirects to /bootstrap (indicates superadmin not configured)
            local HTTP_RESPONSE=$(curl -sS -o /dev/null -w "%{http_code}:%{redirect_url}" \
                --connect-timeout 5 --max-time 10 \
                http://localhost:8081/ 2>/dev/null || echo "000:")

            local HTTP_CODE="${HTTP_RESPONSE%%:*}"
            local REDIRECT_URL="${HTTP_RESPONSE#*:}"

            if [[ "$REDIRECT_URL" == *"/bootstrap"* ]] || [[ "$HTTP_CODE" == "000" ]]; then
                print_warning "Web UI redirects to /bootstrap - superadmin not configured"
                NEEDS_BOOTSTRAP=true

                # Remove partial config to allow fresh bootstrap
                print_status "Removing partial bootstrap config..."
                rm -rf "${RADKIT_DATA_DIR}/service/"
                mkdir -p "${RADKIT_DATA_DIR}"
            else
                print_status "Bootstrap already completed (web UI accessible)"
                return 0
            fi
        else
            # Container not running, can't check web UI - assume settings.toml is valid
            print_status "Container not running - assuming bootstrap completed"
            return 0
        fi
    fi

    if [ "$NEEDS_BOOTSTRAP" = false ]; then
        return 0
    fi

    print_warning "Running bootstrap now..."

    # Stop the container if running (to allow bootstrap to run)
    if docker ps --format '{{.Names}}' | grep -q "^radkit-service$"; then
        print_status "Stopping radkit-service container for bootstrap..."
        docker stop radkit-service >/dev/null 2>&1 || true
    fi

    # Check if the image exists
    if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "${RADKIT_IMAGE}"; then
        # Try to load from tar file if it exists
        if [ -f "/home/cisco/radkit-service.tar" ]; then
            print_status "Loading RADKit image from tar file..."
            docker load -i /home/cisco/radkit-service.tar
        else
            print_error "RADKit image not found and no tar file available"
            print_error "Please ensure radkit-service.tar is in /home/cisco/"
            return 1
        fi
    fi

    print_status "Running RADKit bootstrap with preset password..."

    # Run bootstrap non-interactively by piping password twice (password + confirmation)
    printf '%s\n%s\n' "${SUPERADMIN_PASSWORD}" "${SUPERADMIN_PASSWORD}" | \
        docker run --rm -i --entrypoint radkit-service \
            -v "${RADKIT_DATA_DIR}:/radkit" \
            "${RADKIT_IMAGE}" bootstrap

    if [ $? -eq 0 ]; then
        print_status "Bootstrap completed successfully"
    else
        print_error "Bootstrap failed"
        return 1
    fi

    # Start/restart the service container
    if docker ps -a --format '{{.Names}}' | grep -q "^radkit-service$"; then
        # Container exists - restart it
        print_status "Restarting radkit-service container..."
        docker start radkit-service >/dev/null 2>&1 || true
    else
        # Create new container
        print_status "Creating and starting radkit-service container..."

        local PASS_B64=$(echo -n "${SUPERADMIN_PASSWORD}" | base64)

        docker run -d \
            --name radkit-service \
            --restart=unless-stopped \
            -p 8081:8081 \
            -e "RADKIT_SERVICE_SUPERADMIN_PASSWORD_BASE64=${PASS_B64}" \
            -v "${RADKIT_DATA_DIR}:/radkit" \
            "${RADKIT_IMAGE}"
    fi

    sleep 3

    if docker ps --format '{{.Names}}' | grep -q "^radkit-service$"; then
        print_status "radkit-service container running successfully"
    else
        print_error "Failed to start radkit-service container"
        docker logs radkit-service 2>/dev/null || true
        return 1
    fi
}

#######################################
# Create Directories
#######################################
create_directories() {
    print_header "Creating Directories"

    # Create main scripts directory and all subdirectories
    mkdir -p "${SCRIPTS_DIR}"/{mcp-server,radkit,llm,remote_server,tools}
    print_status "Created ${SCRIPTS_DIR} with subdirectories"

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

    for mapping in "${SCRIPT_MAPPINGS[@]}"; do
        local local_name="${mapping#*|}"
        if [ -f "${SCRIPTS_DIR}/${local_name}" ]; then
            cp "${SCRIPTS_DIR}/${local_name}" "${SCRIPTS_DIR}/${local_name}${BACKUP_SUFFIX}"
            print_status "Backed up ${local_name}"
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
    echo ""

    for mapping in "${SCRIPT_MAPPINGS[@]}"; do
        local github_path="${mapping%|*}"
        local local_name="${mapping#*|}"
        local url="${GITHUB_RAW_BASE}/${github_path}"
        local dest="${SCRIPTS_DIR}/${local_name}"

        # Ensure parent directory exists for files in subdirectories
        mkdir -p "$(dirname "${dest}")"

        echo "Downloading ${local_name}..."
        if curl -sS -f -o "${dest}" "${url}"; then
            print_status "Downloaded ${local_name}"
        else
            print_error "Failed to download ${local_name} from ${url}"
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
        cp "${SCRIPTS_DIR}/mcp-server/setup_mcp.sh" "${MCP_SERVER_DIR}/"
        cp "${SCRIPTS_DIR}/mcp-server/enroll_client.py" "${MCP_SERVER_DIR}/"
        print_status "Copied setup_mcp.sh and enroll_client.py to ${MCP_SERVER_DIR}"
    else
        print_warning "${MCP_SERVER_DIR} does not exist - skipping copy"
        print_warning "Scripts are available in ${SCRIPTS_DIR}/mcp-server/"
    fi
}

#######################################
# Set Permissions
#######################################
set_permissions() {
    print_header "Setting Permissions"

    # Recursively set 755 on all scripts directory
    chmod -R 755 "${SCRIPTS_DIR}"
    print_status "Set permissions (chmod -R 755) on ${SCRIPTS_DIR}"

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
    echo "    fix_scripts.sh"
    echo "    mcp-server/"
    echo "      - setup_mcp.sh"
    echo "      - radkit-mcp-test.sh"
    echo "      - enroll_client.py"
    echo "    radkit/"
    echo "      - radkit-install.sh"
    echo "      - radkit_fixes.sh"
    echo "    llm/"
    echo "      - chat_gpt51.sh, chat_gpt52.sh, check_models.sh"
    echo "    remote_server/"
    echo "      - remote_register.py"
    echo "    tools/"
    echo "      - convert_toolbox_to_openai_tools.py"
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
    echo "  - Container renamed radkit -> radkit-service (if needed)"
    echo "  - RADKit bootstrap completed (if needed)"
    echo "  - radkit-service restart policy set"
    echo "  - R3 Loopback0 configured (203.0.113.99/24)"
    echo ""
    echo "Next step - run MCP server setup:"
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
    fix_container_name
    check_bootstrap
    configure_router
    create_directories
    backup_scripts
    download_scripts
    copy_to_project
    set_permissions
    print_summary
}

main
