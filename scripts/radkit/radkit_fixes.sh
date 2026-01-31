#!/bin/bash
# Recover RADKit after /tmp/radkit was cleared on reboot
# Run with: sudo bash recover_radkit.sh
# These apply some fixes founed on 30-jan that need to be done post install.
# Script may not be needed to be run, if dcloud has our updated images or if 
# instructors have already run this.

# 1. Configure Docker DNS (fixes network resolution issues)
if [ ! -f /etc/docker/daemon.json ]; then
    mkdir -p /etc/docker
    tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "dns": ["8.8.8.8", "8.8.4.4"]
}
EOF
    echo "Created Docker DNS configuration"
    systemctl restart docker
    echo "Restarted Docker"
    sleep 3
else
    echo "Docker daemon.json already exists"
fi

# 2. Pull python image (needed for MCP server)
if ! docker images | grep -q "python.*3.11-slim"; then
    echo "Pulling python:3.11-slim image..."
    docker pull python:3.11-slim
else
    echo "Python 3.11-slim image already present"
fi

# 3. Create exclusion rule (prevents /tmp/radkit from being cleared on future reboots)
if [ ! -f /etc/tmpfiles.d/radkit.conf ]; then
    echo 'x /tmp/radkit' > /etc/tmpfiles.d/radkit.conf
    echo "Created tmpfiles exclusion rule"
else
    echo "Exclusion rule already exists"
fi

# 4. Recreate the missing directory
mkdir -p /tmp/radkit
echo "Created /tmp/radkit directory"

# 5. Start the existing container
docker start radkit
echo "RADKit container started"

# 6. Verify
sleep 2
docker ps | grep radkit && echo "RADKit is running on https://localhost:8081"
