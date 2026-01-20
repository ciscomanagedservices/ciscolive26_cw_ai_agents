#!/usr/bin/bash
# Author: sholl@cisco.com
# Purpose: automate installation of RADKit MCP server into docker container.
# v1.1 9-jan-2026 - Updated for HTTP transport on /mcp endpoint
# v1.0 8-jan-2026 - Initial release

echo "Enrolling client certificates with RADKit."
python3 enroll_client.py
echo "Certificates enrolled."

echo "Creating Dockerfile"

cat > Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends git && rm -rf /var/lib/apt/lists/*
COPY pyproject.toml README.md ./
COPY src/ src/
COPY mcp_server.py .
RUN pip install --no-cache-dir .
CMD ["fastmcp", "run", "src/radkit_mcp/server.py:mcp", "--transport", "http", "--host", "0.0.0.0", "--port", "8000"]
EOF
echo "Dockerfile created."

echo "Creating radkit network"
docker network create radkit-network
docker network connect radkit-network radkit
echo "Radkit network created and connected."

echo "Enter your email used to register radkit:"
read EMAIL

echo "Enter your RADKit Service Serial (from Step 2.2, e.g., xxxx-yyyy-zzzz):"
read RADKIT_SERVICE_SERIAL

IDENTITY_DIR=~/.radkit/identities/prod.radkit-cloud.cisco.com/$EMAIL
echo "Identity directory set to $IDENTITY_DIR"

echo "Creating .env"
cat > .env << EOF
RADKIT_IDENTITY=$EMAIL
RADKIT_DEFAULT_SERVICE_SERIAL=$RADKIT_SERVICE_SERIAL
RADKIT_CERT_B64=$(base64 -w0 $IDENTITY_DIR/certificate.pem)
RADKIT_KEY_B64=$(base64 -w0 $IDENTITY_DIR/private_key_encrypted.pem)
RADKIT_CA_B64=$(base64 -w0 $IDENTITY_DIR/chain.pem)
RADKIT_KEY_PASSWORD_B64=$(echo -n "0e52nsq5jf7f-bxq8whdi7dnT" | base64 -w0)
MCP_TRANSPORT=http
EOF

echo ".env created"

echo "Building mcp server docker container for radkit"
docker build -t radkit-mcp-server .

echo "Running docker for MCP server"
docker run -d --name radkit-mcp --network radkit-network --env-file .env -p 8000:8000 radkit-mcp-server

echo "MCP server for RADKit is now running."
echo ""
echo "MCP endpoint available at: http://<host>:8000/mcp"
echo ""
echo "XDR Workflow Configuration:"
echo "  - URL: http://<host>:8000/mcp"
echo "  - Method: POST"
echo "  - Headers: Content-Type: application/json"
echo "  - Session: Capture Mcp-Session-Id from initialize response"
