data "yandex_compute_image" "routeros-image-1" {
  name = "routeros-image-71rc6"
}

resource "yandex_compute_instance" "map-router" {
  name                      = "map-router"
  hostname                  = "map-router"
  allow_stopping_for_update = true
  platform_id               = "standard-v3"
  zone                      = "ru-central1-a"

  resources {
    cores         = 2
    memory        = 2
    core_fraction = 100
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.routeros-image-1.id
      type     = "network-ssd"
    }
  }

  network_interface {
    subnet_id      = yandex_vpc_subnet.subnet-b.id
    ip_address     = var.router-1-internal-address
    nat            = true
    nat_ip_address = yandex_vpc_address.router-1-address.external_ipv4_address[0].address
  }

  metadata = {
    serial-port-enable = 1
  }
}
