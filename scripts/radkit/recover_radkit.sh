#!/bin/bash
# Recover RADKit after /tmp/radkit was cleared on reboot
# Run with: sudo bash recover_radkit.sh
#
# This should not be needed, unless the dcloud image doesn't get the 30-jan fixes

# 1. Create exclusion rule (prevents /tmp/radkit from being cleared on future reboots)
if [ ! -f /etc/tmpfiles.d/radkit.conf ]; then
    echo 'x /tmp/radkit' > /etc/tmpfiles.d/radkit.conf
    echo "Created tmpfiles exclusion rule"
else
    echo "Exclusion rule already exists"
fi

# 2. Recreate the missing directory
mkdir -p /tmp/radkit
echo "Created /tmp/radkit directory"

# 3. Start the existing container
docker start radkit
echo "RADKit container started"

# 4. Verify
sleep 2
docker ps | grep radkit && echo "RADKit is running on https://localhost:8081"
