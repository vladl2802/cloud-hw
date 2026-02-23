resource "yandex_vpc_security_group" "application_sg" {
  name       = "application-sg"
  network_id = yandex_vpc_network.network_1.id
}

resource "yandex_vpc_security_group" "monitoring_sg" {
  name       = "monitoring-sg"
  network_id = yandex_vpc_network.network_1.id
}

resource "yandex_vpc_security_group" "agent_sg" {
  name       = "agent-sg"
  network_id = yandex_vpc_network.network_1.id
}

resource "yandex_vpc_security_group" "load_target_sg" {
  name       = "load-target-sg"
  network_id = yandex_vpc_network.network_1.id
}

resource "yandex_vpc_security_group" "nat_sg" {
  name       = "nat-sg"
  network_id = yandex_vpc_network.network_1.id
}

# NAT
resource "yandex_vpc_security_group_rule" "nat_ingress_ssh" {
  security_group_binding = yandex_vpc_security_group.nat_sg.id
  direction              = "ingress"
  protocol               = "TCP"
  port                   = 22
  v4_cidr_blocks         = ["0.0.0.0/0"]
}

resource "yandex_vpc_security_group_rule" "nat_egress_all" {
  security_group_binding = yandex_vpc_security_group.nat_sg.id
  direction              = "egress"
  protocol               = "ANY"
  v4_cidr_blocks         = ["0.0.0.0/0"]
  description            = "Allow outbound from NAT VM"
}

resource "yandex_vpc_security_group_rule" "nat_ingress_from_private" {
  security_group_binding = yandex_vpc_security_group.nat_sg.id
  direction              = "ingress"
  protocol               = "ANY"
  from_port              = 0
  to_port                = 65535
  v4_cidr_blocks         = ["192.168.42.0/24"]
  description            = "Forwarding traffic from private subnet to NAT"
}

# Application
resource "yandex_vpc_security_group_rule" "target_egress_all" {
  security_group_binding = yandex_vpc_security_group.application_sg.id
  direction              = "egress"
  protocol               = "ANY"
  v4_cidr_blocks         = ["0.0.0.0/0"]
}

resource "yandex_vpc_security_group_rule" "app_ingress_ssh_from_nat" {
  security_group_binding = yandex_vpc_security_group.application_sg.id
  direction              = "ingress"
  protocol               = "TCP"
  port                   = 22
  security_group_id      = yandex_vpc_security_group.nat_sg.id
  description            = "SSH to application VM from NAT SG"
}

resource "yandex_vpc_security_group_rule" "app_ingress_node_exporter_from_monitoring" {
  security_group_binding = yandex_vpc_security_group.application_sg.id
  direction              = "ingress"
  protocol               = "TCP"
  port                   = 9100
  security_group_id      = yandex_vpc_security_group.monitoring_sg.id
  description            = "Prometheus scrape node_exporter"
}

resource "yandex_vpc_security_group_rule" "app_ingress_icmp" {
  security_group_binding = yandex_vpc_security_group.application_sg.id
  direction              = "ingress"
  protocol               = "ICMP"
  v4_cidr_blocks         = ["192.168.10.0/24"]
  description            = "Allow ping to application VM"
}

resource "yandex_vpc_security_group_rule" "app_ingress_8000_from_monitoring" {
  security_group_binding = yandex_vpc_security_group.application_sg.id
  direction              = "ingress"
  protocol               = "TCP"
  port                   = 8000
  security_group_id      = yandex_vpc_security_group.monitoring_sg.id
  description            = "Allow Prometheus (monitoring) to scrape /metrics on :8000"
}

# Load_target
resource "yandex_vpc_security_group_rule" "target_ingress_http_from_agent" {
  security_group_binding = yandex_vpc_security_group.load_target_sg.id
  direction              = "ingress"
  protocol               = "TCP"
  port                   = 8000
  security_group_id      = yandex_vpc_security_group.agent_sg.id
  description            = "Allow HTTP to app only from agent SG"
}

# Agent
resource "yandex_vpc_security_group_rule" "agent_ingress_ssh" {
  security_group_binding = yandex_vpc_security_group.agent_sg.id
  direction              = "ingress"
  protocol               = "TCP"
  port                   = 22
  v4_cidr_blocks         = ["0.0.0.0/0"]
  description            = "SSH to agent"
}

resource "yandex_vpc_security_group_rule" "agent_egress_https" {
  security_group_binding = yandex_vpc_security_group.agent_sg.id
  direction              = "egress"
  protocol               = "TCP"
  port                   = 443
  v4_cidr_blocks         = ["0.0.0.0/0"]
  description            = "HTTPS to YC APIs (Load Testing)"
}

resource "yandex_vpc_security_group_rule" "agent_egress_to_target" {
  security_group_binding = yandex_vpc_security_group.agent_sg.id
  direction              = "egress"
  protocol               = "ANY"
  from_port              = 0
  to_port                = 65535
  security_group_id      = yandex_vpc_security_group.load_target_sg.id
  description            = "Traffic from agent to target SG"
}

# Monitoring
resource "yandex_vpc_security_group_rule" "monitoring_egress_all" {
  security_group_binding = yandex_vpc_security_group.monitoring_sg.id
  direction              = "egress"
  protocol               = "ANY"
  v4_cidr_blocks         = ["0.0.0.0/0"]
}

resource "yandex_vpc_security_group_rule" "monitoring_egress_node_exporter" {
  security_group_binding = yandex_vpc_security_group.monitoring_sg.id
  direction              = "egress"
  protocol               = "TCP"
  port                   = 9100
  security_group_id      = yandex_vpc_security_group.application_sg.id
  description            = "Allow monitoring to reach node_exporter on application VMs"
}

resource "yandex_vpc_security_group_rule" "monitoring_ingress_ssh_from_nat" {
  security_group_binding = yandex_vpc_security_group.monitoring_sg.id
  direction              = "ingress"
  protocol               = "TCP"
  port                   = 22
  security_group_id      = yandex_vpc_security_group.nat_sg.id
  description            = "SSH to monitoring VM from NAT SG"
}

resource "yandex_vpc_security_group_rule" "monitoring_ingress_icmp" {
  security_group_binding = yandex_vpc_security_group.monitoring_sg.id
  direction              = "ingress"
  protocol               = "ICMP"
  v4_cidr_blocks         = ["192.168.10.0/24"]
  description            = "Allow ping to monitoring VM"
}

resource "yandex_vpc_security_group_rule" "monitoring_egress_8000_to_app" {
  security_group_binding = yandex_vpc_security_group.monitoring_sg.id
  direction              = "egress"
  protocol               = "TCP"
  port                   = 8000
  security_group_id      = yandex_vpc_security_group.application_sg.id
  description            = "Allow monitoring VM to reach application :8000"
}
