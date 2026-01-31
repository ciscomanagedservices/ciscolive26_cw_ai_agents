#!/bin/bash
# RADKit Service Installation Script
# Assumes Docker is already installed
#
# Usage: ./radkit-install.sh [OPTIONS]
#   -t, --tar FILE      Path to radkit-service.tar (default: ./radkit-service.tar)
#   -n, --name NAME     Container name (default: radkit-service)
#   -p, --password PWD  Superadmin password
#   -d, --data-dir DIR  Data directory (default: /tmp/radkit)
#   -s, --skip-bootstrap  Skip bootstrap step (if already done)
#   -h, --help          Show this help
#
# v1.1 31-jan-2026 - embedded DNS, python-lite, and persistent tmp file fixes.

set -e

# Default Configuration
RADKIT_IMAGE="containers.cisco.com/radkit/radkit-service:latest"
RADKIT_TAR="radkit-service.tar"
RADKIT_DATA_DIR="/tmp/radkit"
CONTAINER_NAME="radkit-service"
SUPERADMIN_PASSWORD="0e52nsq5jf7f-bxq8whdi7dnT"
SKIP_BOOTSTRAP=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    head -15 "$0" | tail -10
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tar)
            RADKIT_TAR="$2"
            shift 2
            ;;
        -n|--name)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        -p|--password)
            SUPERADMIN_PASSWORD="$2"
            shift 2
            ;;
        -d|--data-dir)
            RADKIT_DATA_DIR="$2"
            shift 2
            ;;
        -s|--skip-bootstrap)
            SKIP_BOOTSTRAP=true
            shift
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

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed or not in PATH"
    exit 1
fi

print_status "Docker found: $(docker --version)"

# Configure Docker DNS (fixes network resolution issues in some environments)
if [ ! -f /etc/docker/daemon.json ]; then
    print_status "Configuring Docker DNS..."
    mkdir -p /etc/docker
    tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "dns": ["8.8.8.8", "8.8.4.4"]
}
EOF
    systemctl restart docker
    print_status "Docker DNS configured and restarted"
    sleep 3
else
    print_status "Docker daemon.json already exists, skipping DNS config"
fi

# Pull python image (needed for MCP server)
if ! docker images | grep -q "python.*3.11-slim"; then
    print_status "Pulling python:3.11-slim image..."
    docker pull python:3.11-slim
else
    print_status "Python 3.11-slim image already present"
fi

# Check if container already exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    print_warning "Container '${CONTAINER_NAME}' already exists"

    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_status "Container is running. Showing status:"
        docker ps --filter "name=${CONTAINER_NAME}"
        exit 0
    else
        print_status "Container exists but is stopped. Starting it..."
        docker start "${CONTAINER_NAME}"
        docker ps --filter "name=${CONTAINER_NAME}"
        exit 0
    fi
fi

# Load image from tar if file exists
if [[ -f "$RADKIT_TAR" ]]; then
    print_status "Loading RADKit image from ${RADKIT_TAR}..."
    docker load -i "$RADKIT_TAR"
else
    print_warning "Tar file not found: ${RADKIT_TAR}"
    print_status "Checking if image already exists..."

    if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "${RADKIT_IMAGE}"; then
        print_error "Image ${RADKIT_IMAGE} not found. Please provide the tar file or pull the image."
        exit 1
    fi
    print_status "Image already loaded."
fi

# Create tmpfiles exclusion rule (prevents /tmp/radkit from being cleared on reboot)
if [[ "${RADKIT_DATA_DIR}" == /tmp/* ]] && [ ! -f /etc/tmpfiles.d/radkit.conf ]; then
    print_status "Creating tmpfiles exclusion rule for ${RADKIT_DATA_DIR}..."
    echo "x ${RADKIT_DATA_DIR}" > /etc/tmpfiles.d/radkit.conf
    print_status "Exclusion rule created - data will persist across reboots"
fi

# Create data directory
print_status "Creating data directory: ${RADKIT_DATA_DIR}"
mkdir -p "${RADKIT_DATA_DIR}"

# Run bootstrap if not skipped
if [[ "$SKIP_BOOTSTRAP" == false ]]; then
    print_status "Running RADKit bootstrap..."
    print_warning "This will prompt for superadmin password interactively"

    docker run --rm -it --entrypoint radkit-service \
        -v "${RADKIT_DATA_DIR}:/radkit" \
        "${RADKIT_IMAGE}" bootstrap

    print_status "Bootstrap complete"
else
    print_status "Skipping bootstrap (--skip-bootstrap flag set)"
fi

# Start the service container
print_status "Starting RADKit service container..."

PASS_B64=$(echo -n "${SUPERADMIN_PASSWORD}" | base64)

docker run -d \
    --name "${CONTAINER_NAME}" \
    -p 8081:8081 \
    -e "RADKIT_SERVICE_SUPERADMIN_PASSWORD_BASE64=${PASS_B64}" \
    -v "${RADKIT_DATA_DIR}:/radkit" \
    "${RADKIT_IMAGE}"

# Wait for container to start
print_status "Waiting for container to start..."
sleep 3

# Verify container is running
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    print_status "RADKit service started successfully!"
    echo ""
    docker ps --filter "name=${CONTAINER_NAME}"
    echo ""
    print_status "WebUI available at: http://localhost:8081"
    print_status "Superadmin credentials: superadmin / ${SUPERADMIN_PASSWORD}"
else
    print_error "Container failed to start. Checking logs..."
    docker logs "${CONTAINER_NAME}"
    exit 1
fi
