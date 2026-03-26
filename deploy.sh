#!/bin/bash
set -e
echo "=== Qwen Personal Assistant Deploy (llama.cpp + L4) ==="
ansible-playbook ansible/playbook.yml "$@"
echo "Done! Check the debug output above for DNS records."
