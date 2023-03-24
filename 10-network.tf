resource "yandex_vpc_network" "cloud-network" {
  name = "cloud-network"
}

resource "yandex_vpc_address" "router-1-address" {
  name = "router-1-address"
  external_ipv4_address {
    zone_id = "ru-central1-a"
  }
}

resource "yandex_vpc_address" "balancer-6-address" {
  name = "balancer-6-address"
  external_ipv4_address {
    zone_id = "ru-central1-b"
  }
}

resource "yandex_vpc_subnet" "subnet-b" {
  v4_cidr_blocks = [var.SUBNET_B_ADDR]
  name           = "subnet-b"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.cloud-network.id
  route_table_id = yandex_vpc_route_table.map-route-table.id
  dhcp_options {
    domain_name_servers = [var.master-a-internal-address]
  }
}

resource "yandex_vpc_subnet" "subnet-a" {
  v4_cidr_blocks = ["10.252.11.0/24"]
  name           = "subnet-a"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.cloud-network.id
  route_table_id = yandex_vpc_route_table.map-route-table.id
  dhcp_options {
    domain_name_servers = [var.master-a-internal-address]
  }
}

resource "yandex_vpc_route_table" "map-route-table" {
  name       = "map-route-table"
  network_id = yandex_vpc_network.cloud-network.id

  static_route {
    destination_prefix = var.MAP_NETWORK
    next_hop_address   = var.router-1-internal-address
  }

  static_route {
    destination_prefix = var.TION_NET_1
    next_hop_address   = var.router-1-internal-address
  }

  static_route {
    destination_prefix = var.TION_NET_2
    next_hop_address   = var.router-1-internal-address
  }
}
