data "yandex_compute_image" "ubuntu-2204-lts" {
  family = "ubuntu-2204-lts"
}

data "yandex_compute_image" "nat-instance-ubuntu" {
  family = "nat-instance-ubuntu"
}

data "yandex_compute_image" "container-optimized-image" {
  family = "container-optimized-image"
}

resource "yandex_vpc_network" "network-1" {
  name = "network-1"
}

resource "yandex_vpc_subnet" "subnet-1" {
  name           = "subnet-1"
  zone           = var.zone
  network_id     = yandex_vpc_network.network-1.id
  v4_cidr_blocks = ["192.168.10.0/24"]
}

resource "yandex_vpc_route_table" "nat-route" {
  network_id = yandex_vpc_network.network-1.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    next_hop_address   = yandex_compute_instance.nat.network_interface.0.ip_address
  }
}

resource "yandex_vpc_subnet" "subnet-private" {
  name           = "subnet-private"
  zone           = var.zone
  network_id     = yandex_vpc_network.network-1.id
  route_table_id = yandex_vpc_route_table.nat-route.id
  v4_cidr_blocks = ["192.168.42.0/24"]
}

resource "yandex_compute_instance" "logbroker" {
  count = 3
  name  = "logbroker-${count.index}"

  allow_stopping_for_update = true

  resources {
    cores         = 2
    memory        = 1
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu-2204-lts.id
    }
  }
  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-private.id
    nat = false
  }

  metadata = {
    user-data = file("${path.module}/cloud_config.yaml")
  }
}

resource "yandex_compute_instance" "clickhouse" {
  name        = "clickhouse"

  resources {
    cores         = 2
    memory        = 1
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.container-optimized-image.id
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-1.id
    nat       = false
  }

  metadata = {
    user-data = file("${path.module}/cloud_config.yaml")
  }
}


resource "yandex_compute_instance" "reverse-proxy" {
  name = "reverse-proxy"

  allow_stopping_for_update = true

  resources {
    cores         = 2
    memory        = 1
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu-2204-lts.id
    }
  }
  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-1.id
    nat       = true
  }

  metadata = {
    user-data = file("${path.module}/cloud_config.yaml")
  }
}

resource "yandex_compute_instance" "nat" {
  name = "nat"

  allow_stopping_for_update = true

  resources {
    cores         = 2
    memory        = 1
    core_fraction = 5
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.nat-instance-ubuntu.id
    }
  }
  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-1.id
    nat       = true
  }

  metadata = {
    user-data = file("${path.module}/cloud_config.yaml")
  }
}

output "external_ip_nat" {
  value = yandex_compute_instance.nat.network_interface.0.nat_ip_address
}

output "external_ip_reverse_proxy" {
  value = yandex_compute_instance.reverse-proxy.network_interface.0.nat_ip_address
}

output "internal_ip_logbroker" {
  value = yandex_compute_instance.logbroker[*].network_interface.0.ip_address
}

output "internal_ip_clickhouse" {
  value = yandex_compute_instance.clickhouse.network_interface[0].ip_address
}
