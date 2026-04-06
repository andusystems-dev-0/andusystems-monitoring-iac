#!/bin/bash
# Install ArgoCD for Kubernetes
ansible-playbook -i ansible/inventory/monitoring ansible/configurations/argocd.yml --tags argocd,install