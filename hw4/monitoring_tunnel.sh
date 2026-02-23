#!/usr/bin/env bash
set -euo pipefail

NAT_HOST="$(tofu output -raw external_ip_nat)"
MON_HOST="$(tofu output -raw monitoring_private_ip)"

ssh \
  -o StrictHostKeyChecking=no \
  ${SSH_KEY:+-i "$SSH_KEY"} \
  -o ProxyCommand="ssh -o StrictHostKeyChecking=no -W %h:%p -q vladluk@${NAT_HOST}" \
  -N \
  -L "127.0.0.1:3000:127.0.0.1:3000" \
  -L "127.0.0.1:9090:127.0.0.1:9090" \
  "vladluk@${MON_HOST}"
