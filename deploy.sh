#!/bin/bash
set -e
ansible-playbook ansible/playbook.yml -e project_id="${1:?Usage: ./deploy.sh <project-id>}" "${@:2}"
