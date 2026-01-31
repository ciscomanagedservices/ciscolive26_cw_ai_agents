#!/usr/bin/bash
# Author: sholl@cisco.com
# Purpose: automate installation of RADKit MCP server into docker container.
# v2.1 31-jan-2026 - Auto-run enrollment if not found
# v2.0 30-jan-2026 - Rewritten for robustness: DNS check, idempotent, better error handling
# v1.1 9-jan-2026 - Updated for HTTP transport on /mcp endpoint
# v1.0 8-jan-2026 - Initial release

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Hardcoded password for lab environment
RADKIT_PASSWORD="0e52nsq5jf7f-bxq8whdi7dnT"

#######################################
# Pre-flight Checks
#######################################
check_prerequisites() {
  echo "========================================"
  echo "Pre-flight Checks"
  echo "========================================"

  # Check we're in the right directory
  if [[ ! -f "pyproject.toml" ]] || [[ ! -d "src/radkit_mcp" ]]; then
      print_error "Must run from radkit-mcp-server-community directory"
      echo "Current directory: $(pwd)"
      echo "Please run: cd /home/cisco/radkit-mcp-server-community"
      exit 1
  fi
  print_status "Working directory OK"

  # Check RADKit service container is running, start if needed
  if ! docker ps | grep -q radkit-service; then
      print_warning "RADKit service container is not running"

      # Check if container exists but is stopped
      if docker ps -a | grep -q radkit-service; then
          echo "Starting radkit-service container..."
          docker start radkit-service >/dev/null 2>&1
          sleep 3

          if docker ps | grep -q radkit-service; then
              print_status "RADKit service container started"
          else
              print_error "Failed to start radkit-service container"
              echo "Check logs with: docker logs radkit-service"
              exit 1
          fi
      else
          print_error "RADKit service container does not exist"
          echo "Please run the RADKit installation script first"
          exit 1
      fi
  else
      print_status "RADKit service container is running"
  fi

  # Check Docker is available
  if ! command -v docker &> /dev/null; then
      print_error "Docker is not installed or not in PATH"
      exit 1
  fi
  print_status "Docker available"
}

#######################################
# DNS Check and Fix
#######################################
check_dns() {
  echo ""
  echo "========================================"
  echo "Checking DNS Resolution"
  echo "========================================"

  if ! getent hosts docker.io >/dev/null 2>&1; then
      print_warning "DNS resolution failed for docker.io"
      echo "Adding Google DNS servers..."

      # Backup existing resolv.conf
      cp /etc/resolv.conf /etc/resolv.conf.bak 2>/dev/null || true

      # Add Google DNS (prepend to existing)
      {
          echo "nameserver 8.8.8.8"
          echo "nameserver 8.8.4.4"
          cat /etc/resolv.conf.bak 2>/dev/null || true
      } > /etc/resolv.conf.new
      mv /etc/resolv.conf.new /etc/resolv.conf

      # Verify fix worked
      sleep 2
      if ! getent hosts docker.io >/dev/null 2>&1; then
          print_error "DNS still not working after adding Google DNS"
          echo "Please check your network configuration"
          exit 1
      fi
      print_status "DNS configured successfully"
  else
      print_status "DNS resolution OK"
  fi
}

#######################################
# Check Enrollment
#######################################
check_enrollment() {
  echo ""
  echo "========================================"
  echo "Checking RADKit Enrollment"
  echo "========================================"

  echo "Enter your email used to register RADKit:"
  read -r EMAIL

  if [[ -z "$EMAIL" ]]; then
      print_error "Email cannot be empty"
      exit 1
  fi

  IDENTITY_DIR=~/.radkit/identities/prod.radkit-cloud.cisco.com/$EMAIL

  if [[ ! -d "$IDENTITY_DIR" ]] || [[ ! -f "$IDENTITY_DIR/certificate.pem" ]]; then
      print_warning "RADKit enrollment not found for $EMAIL"
      echo ""
      echo "Running enrollment process..."
      echo ""

      # Check if enroll_client.py exists
      if [[ ! -f "enroll_client.py" ]]; then
          print_error "enroll_client.py not found in current directory"
          exit 1
      fi

      # Run enrollment script with the email pre-filled via stdin
      # The script will handle radkit_client installation if needed
      echo "$EMAIL" | python3 enroll_client.py

      # Verify enrollment succeeded
      if [[ ! -d "$IDENTITY_DIR" ]] || [[ ! -f "$IDENTITY_DIR/certificate.pem" ]]; then
          print_error "Enrollment failed - certificates not found after enrollment"
          echo "Please run enrollment manually: python3 enroll_client.py"
          exit 1
      fi
      print_status "RADKit enrollment completed for $EMAIL"
  else
      print_status "RADKit enrollment found for $EMAIL"
  fi

  # Export for use in other functions
  export EMAIL
  export IDENTITY_DIR
}

#######################################
# Setup Docker Network
#######################################
setup_network() {
  echo ""
  echo "========================================"
  echo "Setting Up Docker Network"
  echo "========================================"

  # Create network if it doesn't exist
  if docker network inspect radkit-network >/dev/null 2>&1; then
      print_status "Network radkit-network already exists"
  else
      docker network create radkit-network
      print_status "Created network radkit-network"
  fi

  # Connect RADKit service to network (ignore if already connected)
  if docker network inspect radkit-network | grep -q radkit-service; then
      print_status "radkit-service already connected to network"
  else
      docker network connect radkit-network radkit-service 2>/dev/null || true
      print_status "Connected radkit-service to network"
  fi
}

#######################################
# Create Environment File
#######################################
create_env() {
  echo ""
  echo "========================================"
  echo "Creating Environment File"
  echo "========================================"

  echo "Enter your RADKit Service Serial (from Step 2.2, e.g., xxxx-yyyy-zzzz):"
  read -r RADKIT_SERVICE_SERIAL

  if [[ -z "$RADKIT_SERVICE_SERIAL" ]]; then
      print_error "Service serial cannot be empty"
      exit 1
  fi

  echo "Creating .env file..."
  cat > .env << EOF
RADKIT_IDENTITY=$EMAIL
RADKIT_DEFAULT_SERVICE_SERIAL=$RADKIT_SERVICE_SERIAL
RADKIT_CERT_B64=$(base64 -w0 "$IDENTITY_DIR/certificate.pem")
RADKIT_KEY_B64=$(base64 -w0 "$IDENTITY_DIR/private_key_encrypted.pem")
RADKIT_CA_B64=$(base64 -w0 "$IDENTITY_DIR/chain.pem")
RADKIT_KEY_PASSWORD_B64=$(echo -n "$RADKIT_PASSWORD" | base64 -w0)
MCP_TRANSPORT=http
EOF

  print_status ".env file created"
}

#######################################
# Create Dockerfile
#######################################
create_dockerfile() {
  echo ""
  echo "========================================"
  echo "Creating Dockerfile"
  echo "========================================"

  cat > Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends git && rm -rf /var/lib/apt/lists/*
COPY pyproject.toml README.md ./
COPY src/ src/
RUN pip install --no-cache-dir .
CMD ["fastmcp", "run", "src/radkit_mcp/server.py:mcp", "--transport", "http", "--host", "0.0.0.0", "--port", "8000"]
EOF

  print_status "Dockerfile created"
}

#######################################
# Build Docker Image
#######################################
build_image() {
  echo ""
  echo "========================================"
  echo "Building MCP Server Docker Image"
  echo "========================================"

  echo "This may take a few minutes..."
  if docker build -t radkit-mcp-server . ; then
      print_status "Docker image built successfully"
  else
      print_error "Docker build failed"
      echo ""
      echo "Common issues:"
      echo "  - DNS not resolving (check /etc/resolv.conf)"
      echo "  - Network connectivity issues"
      echo "  - Missing files in current directory"
      exit 1
  fi
}

#######################################
# Run Container
#######################################
run_container() {
  echo ""
  echo "========================================"
  echo "Starting MCP Server Container"
  echo "========================================"

  # Remove existing container if present
  if docker ps -a | grep -q radkit-mcp; then
      print_warning "Removing existing radkit-mcp container..."
      docker rm -f radkit-mcp >/dev/null 2>&1 || true
  fi

  # Start new container with restart policy for persistence
  docker run -d \
      --restart=unless-stopped \
      --name radkit-mcp \
      --network radkit-network \
      --env-file .env \
      -p 8000:8000 \
      radkit-mcp-server

  print_status "Container started"

  # Wait for container to initialize
  echo "Waiting for MCP server to initialize..."
  sleep 5

  # Verify container is running
  if docker ps | grep -q radkit-mcp; then
      print_status "MCP server container is running"
  else
      print_error "Container failed to start"
      echo "Check logs with: docker logs radkit-mcp"
      exit 1
  fi
}

#######################################
# Print Success Message
#######################################
print_success() {
  echo ""
  echo "========================================"
  echo -e "${GREEN}MCP Server Setup Complete!${NC}"
  echo "========================================"
  echo ""
  echo "MCP endpoint available at: http://198.18.1.250:8000/mcp"
  echo ""
  echo "Next steps:"
  echo "  1. Run the test script to verify:"
  echo "     /home/cisco/scripts/mcp/radkit-mcp-test.sh"
  echo ""
  echo "  2. Continue with Step 3.6 in the lab guide"
  echo ""
}

#######################################
# Main
#######################################
main() {
  echo ""
  echo "========================================"
  echo "RADKit MCP Server Setup"
  echo "========================================"
  echo ""

  check_prerequisites
  check_dns
  check_enrollment
  setup_network
  create_env
  create_dockerfile
  build_image
  run_container
  print_success
}

main
