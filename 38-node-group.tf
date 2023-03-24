resource "yandex_compute_instance_group" "node-group-01" {
  name               = "node-group-01"
  service_account_id = yandex_iam_service_account.deployment-sa.id

  instance_template {
    name               = "docker-node-{instance.index}"
    hostname           = "docker-node-{instance.index}"
    service_account_id = yandex_iam_service_account.deployment-sa.id
    platform_id        = "standard-v3"

    resources {
      memory        = 16
      cores         = 2
      core_fraction = 100
    }

    boot_disk {
      mode = "READ_WRITE"
      initialize_params {
        image_id = "fd8c6grkhgdroacgig84"
        size     = 16
      }
    }

    network_interface {
      subnet_ids = [yandex_vpc_subnet.subnet-a.id]
    }

    metadata = {
      user-data = data.template_file.default_cloud_config.rendered
      traefik   = "false"
    }
  }

  allocation_policy {
    zones = [yandex_vpc_subnet.subnet-a.zone]
  }

  scale_policy {
    fixed_scale {
      size = 2
    }
  }

  load_balancer {
    target_group_name = "tg-node-docker-ig"
  }

  deploy_policy {
    max_unavailable = 1
    max_creating    = 1
    max_expansion   = 1
    max_deleting    = 1
  }

  health_check {
    healthy_threshold   = 2
    interval            = 2
    timeout             = 1
    unhealthy_threshold = 2

    http_options { # instance healthy when nomad is up
      path = "/v1/agent/health"
      port = "4646"
    }
  }
}
