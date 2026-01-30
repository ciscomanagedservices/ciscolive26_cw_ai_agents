#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: $0 <api-key>"
    exit 1
fi

curl -s http://ec2-54-224-217-248.compute-1.amazonaws.com:4000/models \
    -H "Authorization: Bearer $1" | jq .
