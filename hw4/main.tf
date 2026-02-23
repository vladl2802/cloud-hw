data "yandex_compute_image" "ubuntu_2204_lts" {
  family = "ubuntu-2204-lts"
}

data "yandex_compute_image" "nat_instance_ubuntu" {
  family = "nat-instance-ubuntu"
}

data "yandex_compute_image" "container_optimized_image" {
  family = "container-optimized-image"
}

resource "yandex_iam_service_account" "sa_puller" {
  name = "sa-registry-puller"
}

resource "yandex_resourcemanager_folder_iam_member" "sa_puller_role" {
  folder_id = var.folder_id
  role = "container-registry.images.puller"
  member = "serviceAccount:${yandex_iam_service_account.sa_puller.id}"
}

resource "yandex_iam_service_account" "sa_loadtest" {
  name = "sa-loadtest"
}

resource "yandex_resourcemanager_folder_iam_member" "sa_loadtest_role" {
  folder_id = var.folder_id
  role      = "loadtesting.generatorClient"
  member    = "serviceAccount:${yandex_iam_service_account.sa_loadtest.id}"
}

resource "yandex_container_registry" "registry" {
  name  = "registry"
}

resource "yandex_vpc_network" "network_1" {
  name = "network-1"
}

resource "yandex_vpc_subnet" "subnet_1" {
  name           = "subnet-1"
  zone           = var.zone
  network_id     = yandex_vpc_network.network_1.id
  v4_cidr_blocks = ["192.168.10.0/24"]
}

resource "yandex_vpc_route_table" "nat_route" {
  network_id = yandex_vpc_network.network_1.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    next_hop_address   = yandex_compute_instance.nat.network_interface[0].ip_address
  }
}

resource "yandex_vpc_subnet" "subnet_private" {
  name           = "subnet-private"
  zone           = var.zone
  network_id     = yandex_vpc_network.network_1.id
  route_table_id = yandex_vpc_route_table.nat_route.id
  v4_cidr_blocks = ["192.168.42.0/24"]
}

resource "yandex_compute_instance" "nat" {
  name = "nat"

  allow_stopping_for_update = true

  resources {
    cores = 2
    memory = 1
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.nat_instance_ubuntu.id
    }
  }
  network_interface {
    subnet_id = yandex_vpc_subnet.subnet_1.id
    nat = true
    security_group_ids = [yandex_vpc_security_group.nat_sg.id, yandex_vpc_security_group.monitoring_sg.id]
  }

  metadata = {
    user-data = file("${path.module}/cloud_config.yaml")
  }
}

resource "yandex_compute_instance" "application" {
  name = "application"

  service_account_id = yandex_iam_service_account.sa_puller.id

  allow_stopping_for_update = true

  resources {
    cores = 8
    memory = 8
    core_fraction = 100
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.container_optimized_image.id
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet_private.id
    nat = false
    security_group_ids = [yandex_vpc_security_group.application_sg.id, yandex_vpc_security_group.load_target_sg.id]
  }

  metadata = {
    user-data = file("${path.module}/cloud_config.yaml")
  }
}

resource "yandex_compute_instance" "monitoring" {
  name = "monitoring"

  resources {
    cores         = 2
    memory        = 1
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.container_optimized_image.id
    }
  }

  network_interface {
    subnet_id           = yandex_vpc_subnet.subnet_private.id
    nat                 = false
    security_group_ids  = [yandex_vpc_security_group.monitoring_sg.id]
  }

  metadata = {
    user-data = file("${path.module}/cloud_config.yaml")
  }
}
