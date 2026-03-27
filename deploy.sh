#!/bin/bash
set -e
ansible-playbook ansible/playbook.yml -e project_id=broze-net "$@"
