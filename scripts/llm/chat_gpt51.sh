#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: $0 <api-key>"
    exit 1
fi

curl -s https://ciscolive-llm.com/chat/completions \
    -H "Authorization: Bearer $1" \
    -H "Content-Type: application/json" \
    -d '{"model":"gpt-5.1","messages":[{"role":"user","content":"Hello!"}]}'
