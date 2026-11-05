terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
}

variable "yc_token" {}
variable "yc_cloud_id" {}
variable "yc_folder_id" {}

provider "yandex" {
  token     = var.yc_token
  cloud_id  = var.yc_cloud_id
  folder_id = var.yc_folder_id
  zone      = "ru-central1-a"
}

resource "yandex_vpc_network" "net" {
  name = "hw-ha-net"
}

resource "yandex_vpc_subnet" "subnet_a" {
  name            = "hw-ha-subnet-a"
  zone            = "ru-central1-a"
  network_id      = yandex_vpc_network.net.id
  v4_cidr_blocks = ["10.0.1.0/24"]
}

resource "yandex_vpc_subnet" "subnet_d" {
  name            = "hw-ha-subnet-d"
  zone            = "ru-central1-d"
  network_id      = yandex_vpc_network.net.id
  v4_cidr_blocks = ["10.0.3.0/24"]
}

resource "yandex_compute_instance" "vm" {
  count = 2
  name  = "netology-vm-${count.index + 1}"
  zone  = count.index == 0 ? "ru-central1-a" : "ru-central1-d"
  platform_id = "standard-v3"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd8emvfmfoaordspe1jr"
    }
  }

  network_interface {
    subnet_id = count.index == 0 ? yandex_vpc_subnet.subnet_a.id : yandex_vpc_subnet.subnet_d.id
    nat       = true
  }

  metadata = {
    user-data = <<EOF
#!/bin/bash
apt-get update
apt-get install -y nginx
systemctl enable nginx
systemctl start nginx
EOF
  }
}

resource "yandex_lb_target_group" "tg" {
  name = "nginx-tg"

  dynamic "target" {
    for_each = yandex_compute_instance.vm
    content {
      subnet_id = target.value.network_interface[0].subnet_id
      address   = target.value.network_interface[0].ip_address
    }
  }
}

resource "yandex_lb_network_load_balancer" "nlb" {
  name = "nginx-nlb"

  listener {
    name = "http-listener"
    port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.tg.id

    healthcheck {
      name = "http-check"
      http_options {
        port = 80
        path = "/"
      }
    }
  }
}

output "lb_ip" {
  value = one(one(yandex_lb_network_load_balancer.nlb.listener).external_address_spec).address
}