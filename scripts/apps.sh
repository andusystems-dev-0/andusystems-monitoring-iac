#!/bin/bash
# Install Monitoring Apps for Kubernetes
ansible-playbook -i ansible/inventory/monitoring ansible/configurations/apps.yml --tags apps,install -K