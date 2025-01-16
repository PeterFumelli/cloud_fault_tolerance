terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
}

variable "yandex_cloud_token" {
  type        = string
  description = "Enter your Yandex Cloud token"
}

provider "yandex" {
  token     = var.yandex_cloud_token
  cloud_id  = "cloud-pfhositru"
  folder_id = "b1g9fkgcb4m0n7vhc475"
  zone      = "ru-central1-a"
}

# Создание новой сети
resource "yandex_vpc_network" "network-1" {
  name = "new-network"
}

# Создание новой подсети
resource "yandex_vpc_subnet" "subnet-1" {
  name           = "new-subnet"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.network-1.id
  v4_cidr_blocks = ["192.168.100.0/24"]
}

resource "yandex_compute_instance" "vm" {
  count        = 2
  name         = "example-vm-${count.index}"
  zone         = "ru-central1-a"
  platform_id  = "standard-v2"
  resources {
    cores  = 2
    memory = 2
  }
  boot_disk {
    initialize_params {
      image_id = "fd876gids9srs8ma0592" # Замените на актуальный ID образа
    }
  }
  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-1.id
    nat       = true
  }
  metadata = {
    ssh-keys = "user:${file("~/.ssh/id_rsa.pub")}"
    user-data = <<-EOF
      #cloud-config
      packages:
        - nginx
      runcmd:
        - systemctl start nginx
        - systemctl enable nginx
    EOF
  }
}

# Создание таргет-группы
resource "yandex_lb_target_group" "example" {
  name      = "example-target-group"
  region_id = "ru-central1"

  target {
    subnet_id = yandex_vpc_subnet.subnet-1.id
    address   = yandex_compute_instance.vm[0].network_interface[0].ip_address
  }

  target {
    subnet_id = yandex_vpc_subnet.subnet-1.id
    address   = yandex_compute_instance.vm[1].network_interface[0].ip_address
  }
}

# Создание сетевого балансировщика нагрузки
resource "yandex_lb_network_load_balancer" "example" {
  name = "example-nlb"

  listener {
    name = "my-listener"
    port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.example.id

    healthcheck {
      name = "http"
      http_options {
        port = 80
        path = "/"
      }
    }
  }
}

# Вывод IP-адресов виртуальных машин
output "vm_external_ips" {
  value = yandex_compute_instance.vm[*].network_interface[0].nat_ip_address
}

# Вывод IP-адреса балансировщика
output "load_balancer_ip" {
  value = [for listener in yandex_lb_network_load_balancer.example.listener : listener.external_address_spec][0]
}
