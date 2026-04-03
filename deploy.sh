#!/bin/bash
set -e
ansible-playbook ansible/playbook.yml "$@"
