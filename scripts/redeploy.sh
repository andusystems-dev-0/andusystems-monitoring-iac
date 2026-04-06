#!/bin/bash
# Do a full redeploy of everything
ansible-playbook -i ansible/inventory/monitoring ansible/configurations/monitoring.yml --tags vms,kubernetes,apps,install -K