output "external_ip_nat" {
  value = yandex_compute_instance.nat.network_interface[0].nat_ip_address
}

output "application_private_ip" {
  value = yandex_compute_instance.application.network_interface[0].ip_address
}

output "monitoring_private_ip" {
    value = yandex_compute_instance.monitoring.network_interface[0].ip_address
}

output "registry_id" {
  value = yandex_container_registry.registry.id
}
