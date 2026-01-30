# Plan to Fix Lab 3

## Summary of Issues Identified

From testing, the following problems were encountered:

1. **DNS not configured** - Docker build fails trying to resolve `registry-1.docker.io`
2. **radkit_client not installed** - The enroll script fails because the Python package isn't installed
3. **Script not idempotent** - Fails on rerun with "network already exists" errors
4. **OAuth URL not highlighted** - Users don't know they need to open the URL manually
5. **Private key password unclear** - Users don't know to use the hardcoded password
6. **Path issues** - Script assumes wrong working directory/paths
7. **mcp_server.py file missing** - Dockerfile tries to COPY a file that doesn't exist
8. **Container name `radkit` not found** - Script tries to connect to wrong container name (`radkit` vs `radkit-service`)

---

## Part A: Lab Guide (lab3.md) Changes

### Section 1.2 - Remove Git Clone Requirement

**Current:** Instructs users to clone the repo

**Change:**
- Remove the clone instructions since files are pre-loaded
- Keep as a reference note only
- Add check for RADKit container with `docker ps | grep radkit`
- Add restart instructions if not running

**New text:**
```markdown
### 1.2 Verify RADKit Service is Running

The RADKit service container should already be loaded on the ubuntu-server.

1. Verify the container is running:
   ```bash
   docker ps | grep radkit
   ```

2. If the container is not running, try to restart it:
   ```bash
   docker start radkit-service
   ```

3. If it still doesn't start, ask your instructor for assistance.

!!! note "Pre-loaded Files"
    The following files are pre-loaded on the ubuntu-server in `/home/cisco/`:

    - `radkit-service.tar` - RADKit Docker image (already loaded)
    - `radkit-mcp-server-community/` - MCP server source code repository
    - `scripts/mcp/` - Setup scripts for this lab
```

### Section 2.3 - Fix "Enable Terminal Management" Wording

**Current:** "Enable Terminal Management"

**Change:** Update step 4 to be more specific about the UI:

**New text:**
```markdown
4. Under <em class="lab-warning">Available Management Protocols</em>, click the checkbox for <em class="lab-warning">Terminal</em>
```

### Section 3.2 - Fix Copy Commands

**Current:**
```bash
cp /root/ciscolive26_cw_ai_agents/scripts/mcp-server/setup_mcp.sh .
cp /root/ciscolive26_cw_ai_agents/scripts/mcp-server/enroll_client.py .
```

**Change:** Update paths to use pre-loaded scripts:
```bash
cp /home/cisco/scripts/mcp/setup_mcp.sh .
cp /home/cisco/scripts/mcp/enroll_client.py .
```

### Section 3.3 - Major Rewrite for Enrollment Process

**Current:** Just says "Run the setup script"

**Change:** Split into multiple sub-steps with detailed instructions:

**New text:**
```markdown
### 3.3 Install RADKit Client

Before running the setup script, you must install the RADKit client Python package:

1. Install the RADKit client from PyPI:
   ```bash
   python3 -m pip install cisco_radkit_client==1.9.2 --break-system-packages
   ```

   > **Note:** The `--break-system-packages` flag is required on Ubuntu 24.04 due to PEP 668 externally-managed environment restrictions.

### 3.4 Enroll RADKit Client Certificates

The enrollment process authenticates you with RADKit cloud and generates client certificates.

1. Run the enrollment script:
   ```bash
   python3 enroll_client.py
   ```

2. When prompted, enter your Cisco email address (same one used in Step 2.2)

3. **IMPORTANT:** The script will display a URL like this:
   ```
   https://id.cisco.com/oauth2/default/v1/authorize?response_type=code&client_id=radkit_prod...
   ```

   !!! warning "Action Required"
       You **MUST** copy this URL and paste it into your browser to complete OAuth authentication. The script will wait for you to complete the login.

4. After completing OAuth in your browser, return to the terminal

5. When prompted for a private key password, enter:
   ```
   0e52nsq5jf7f-bxq8whdi7dnT
   ```

   > **Note:** This password is hardcoded in the setup script to simplify the lab. In production, you would use a unique, strong password.

6. Confirm the password when prompted

!!! info "More Information"
    For detailed information about setting up the MCP server outside of this lab, see the official documentation at [https://github.com/CiscoDevNet/radkit-mcp-server-community](https://github.com/CiscoDevNet/radkit-mcp-server-community)

### 3.5 Run the MCP Setup Script

Now run the setup script to build and start the MCP server container:

1. Run the setup script:
   ```bash
   ./setup_mcp.sh
   ```

2. When prompted, enter:
   - Your **email address** (the same one used for RADKit registration)
   - Your **RADKit Service Serial** (the Service ID from Step 2.2, e.g., `xxxx-yyyy-zzzz`)

The script will:
- Check DNS configuration and fix if needed
- Create a Docker network for RADKit communication
- Build the MCP server Docker image
- Start the MCP server container on port 8000

!!! tip "Re-running the Script"
    The script is designed to be idempotent. If you need to re-run it (e.g., after fixing an error), it will clean up existing resources automatically.
```

### Section 3.4 → 3.6 - Renumber Verify MCP Server

Renumber from 3.4 to 3.6 due to new sections added above.

---

## Part B: Script (setup_mcp.sh) Improvements

### Full Rewrite

```bash
#!/usr/bin/bash
# Author: sholl@cisco.com
# Purpose: automate installation of RADKit MCP server into docker container.
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

    # Check RADKit service container is running
    if ! docker ps | grep -q radkit-service; then
        print_error "RADKit service container is not running"
        echo "Try: docker start radkit-service"
        exit 1
    fi
    print_status "RADKit service container is running"

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
        print_error "RADKit enrollment not found for $EMAIL"
        echo ""
        echo "Please run the enrollment first:"
        echo "  python3 enroll_client.py"
        echo ""
        echo "Then re-run this script."
        exit 1
    fi
    print_status "RADKit enrollment found for $EMAIL"

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

    # Start new container
    docker run -d \
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
```

---

## Part C: Script (enroll_client.py) Improvements

### Full Rewrite

```python
#!/usr/bin/env python3
"""
RADKit Client Enrollment Script

This script enrolls your RADKit client for certificate authentication.
"""

import sys
import os

# Check if radkit_client is installed
try:
    from radkit_client.sync import Client
except ImportError:
    print("Error: radkit_client not installed")
    print("")
    print("Please install RADKit client first:")
    print("  python3 -m pip install cisco_radkit_client==1.9.2 --break-system-packages")
    print("")
    sys.exit(1)

# Hardcoded password for lab environment
RADKIT_PASSWORD = "0e52nsq5jf7f-bxq8whdi7dnT"

def main():
    print("=" * 70)
    print("RADKit Client Enrollment")
    print("=" * 70)
    print("")
    print("This script will enroll your RADKit client for certificate authentication.")
    print("")
    print("You will:")
    print("  1. Enter your Cisco email address")
    print("  2. Authenticate via SSO (copy URL to browser)")
    print("  3. Use the lab password for your private key")
    print("")
    print("=" * 70)
    print("")

    # Get email
    email = input("Enter your Cisco email address: ").strip()
    if not email:
        print("Error: Email cannot be empty")
        sys.exit(1)

    print("")
    print(f"Enrolling as: {email}")
    print("")
    print("=" * 70)
    print("IMPORTANT: OAuth Authentication Required")
    print("=" * 70)
    print("")
    print("A URL will appear below. You MUST:")
    print("  1. Copy the ENTIRE URL (starts with https://id.cisco.com/...)")
    print("  2. Paste it into your browser")
    print("  3. Complete the Cisco SSO login")
    print("  4. Return here after login completes")
    print("")
    print(f"Private key password (use this when prompted): {RADKIT_PASSWORD}")
    print("")
    input("Press Enter to continue...")
    print("")

    try:
        with Client.create() as client:
            # Perform SSO login
            client.sso_login(domain="PROD", identity=email)

            print("")
            print("=" * 70)
            print("SSO authentication successful!")
            print("=" * 70)
            print("")
            print(f"Now enrolling client certificate...")
            print(f"When prompted for password, enter: {RADKIT_PASSWORD}")
            print("")

            # Enroll client
            client.enroll_client()

            print("")
            print("=" * 70)
            print("Enrollment Complete!")
            print("=" * 70)
            print("")
            print(f"Certificates saved to: ~/.radkit/identities/prod.radkit-cloud.cisco.com/{email}/")
            print("")
            print("You can now run: ./setup_mcp.sh")
            print("")

    except KeyboardInterrupt:
        print("")
        print("Enrollment cancelled by user")
        sys.exit(1)
    except Exception as e:
        print("")
        print(f"Error during enrollment: {e}")
        print("")
        print("If SSO failed, make sure you:")
        print("  1. Copied the FULL URL to your browser")
        print("  2. Completed the login successfully")
        print("  3. Have network access to id.cisco.com")
        print("")
        sys.exit(1)

if __name__ == "__main__":
    main()
```

---

## Files to Modify

| File | Changes |
|------|---------|
| `lab-guide/docs/lab3.md` | Update sections 1.2, 2.3, 3.2-3.6 as described above |
| `scripts/mcp-server/setup_mcp.sh` | Full rewrite with robustness improvements |
| `scripts/mcp-server/enroll_client.py` | Full rewrite with better UX and error handling |

---

## Testing Checklist

After implementing changes, verify:

- [ ] Script runs successfully on first execution
- [ ] Script runs successfully on re-execution (idempotent)
- [ ] DNS check works and fixes DNS if needed
- [ ] Enrollment process is clear with OAuth URL instructions
- [ ] Container builds successfully
- [ ] Container starts and stays running
- [ ] MCP test script passes all 3 tests
- [ ] Lab guide instructions match actual script behavior
