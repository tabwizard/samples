data "template_file" "default_cloud_config" {
  template = file("./templates/default_cloud_config.yml")
}

resource "yandex_compute_disk" "builder-01-disk" {
  name = "builder-01-disk"
  type = "network-hdd"
  size = 64
}

resource "yandex_compute_instance" "builder-01" {
  name                      = "builder-01"
  hostname                  = "builder-01"
  allow_stopping_for_update = true
  platform_id               = "standard-v3"

  service_account_id = yandex_iam_service_account.deployment-sa.id
  zone               = "ru-central1-a"

  resources {
    cores         = 2
    memory        = 4
    core_fraction = 100
  }

  boot_disk {
    initialize_params {
      size     = 24
      image_id = var.IMAGE_ID
      type     = "network-ssd"
    }
  }

  secondary_disk {
    disk_id = yandex_compute_disk.builder-01-disk.id
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-b.id
  }

  metadata = {
    user-data = data.template_file.default_cloud_config.rendered
  }
}
