#!/bin/bash

# Create VMs on Proxmox
ansible-playbook -i ansible/inventory/monitoring ansible/configurations/roles/kubernetes.yml --tags kubernetes,install