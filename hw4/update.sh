#!/usr/bin/env bash
# tofu apply
tofu output -json > terraform.out
jinja2 -f json ansible_inventory.j2 terraform.out -o ansible_inventory
ansible-playbook application/ansible/playbook.yml
ansible-playbook monitoring/ansible/playbook.yml
