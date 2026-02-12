terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  zone = "ru-central1-d"
}

resource "yandex_compute_instance" "compute-vm-2-2-15-hdd-1770306148557" {
  boot_disk {
    initialize_params {
      name       = "disk-ubuntu-24-04-lts-1770306150306"
      type       = "network-hdd"
      size       = 15
      block_size = 4096
      image_id   = "fd8vhban0amqsqutsjk7"
    }
    auto_delete = true
  }
  folder_id = "b1gdv3sgqfl4uv9o1b1c"
  hostname  = "compute-vm-2-2-15-hdd-1770306148557"
  metadata = {
    user-data = templatefile("${path.module}/cloud-config.yaml", {
      script_content = base64encode(file("${path.module}/run-server.sh"))
    })
    ssh-keys  = "vladluk:ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINufx/2mS4T3PsIXwlZT6OT5IOFDxu0yc8QCfSk8jJgY vladl2802@yandex.ru"
  }
  name = "compute-vm-2-2-15-hdd-1770306148557"
  network_interface {
    subnet_id = "fl8m8r9au1ce5afupv64"
    nat       = true
  }
  platform_id = "standard-v3"
  resources {
    memory        = 2
    cores         = 2
    core_fraction = 100
  }
  scheduling_policy {
    preemptible = true
  }
}
