variable "version" {
  type    = string
  default = 2
}

variable "sensor_image" {
  type    = string
  default = "cr.yandex/xxxxxxxxxxxxx/map/sensorvalues:dev"
}

variable "auth_image" {
  type    = string
  default = "cr.yandex/xxxxxxxxxxxxx/map/authorization:dev"
}

variable "map_image" {
  type    = string
  default = "cr.yandex/xxxxxxxxxxxxx/map/magicairpro:dev"
}

variable "front_image" {
  type    = string
  default = "cr.yandex/xxxxxxxxxxxxx/map/frontend:dev"
}

variable "kontur" {
  type    = string
  default = "develop"
}
{{ $targkontur := env "KONTUR_TEMPLATE" }}

job "magicairpro" {
  datacenters = ["yc"]
  type        = "service"

  namespace = "${var.kontur}"

  vault {
    policies = ["read"]
  }

  group "map" {
    constraint {
      attribute = "${attr.unique.hostname}"
      operator  = "regexp"
      value     = "docker-node-*"
    }

    restart {
      attempts = 10
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }

    network {
      port "rabbitmq" {
        to = 5672
      }
      port "rabbitmq_ui" {
        to = 15672
      }
      port "rabbitmq_mqtt" {
        to = 8883
      }
      port "sensor_grpc" {
        to = 4010
      }
      port "sensor_api" {
        to = 4003
      }
      port "auth_http" {
        to = 80
      }
      port "map_http" {
        to = 80
      }
      port "front_http" {
        to = 80
      }
    }

    task "rabbitmq" {
      driver = "docker"
      lifecycle {
        hook    = "prestart"
        sidecar = true
      }

      template {
        data = <<-EOH
        [rabbitmq_management,rabbitmq_management_agent,rabbitmq_mqtt,rabbitmq_prometheus,rabbitmq_web_dispatch,rabbitmq_web_mqtt].
        EOH
        destination = "enabled_plugins"
      }

      template {
        data = <<-EOH
        mqtt.listeners.tcp.default = 8883
        mqtt.allow_anonymous  = false
{{ with secret (print "secrets/map/kontur/" $targkontur "/common") }} 
        mqtt.default_user     = {{ .Data.ServiceBus__RabbitMQ__UserName }}
        mqtt.default_pass     = {{ .Data.ServiceBus__RabbitMQ__Password }}
{{ end }}
        mqtt.vhost            = /
        mqtt.exchange         = amq.topic
        # 24 hours by default
        mqtt.subscription_ttl = 86400000
        mqtt.prefetch         = 10
        EOH
        destination = "10-defaults.conf"
      }

      meta {
        version = "${var.version}"
      }
    
      config {
        image         = "rabbitmq:3-management"
        force_pull    = "true"
        volumes       = [ "/opt/nomad/data/volume/rmq/${var.kontur}:/var/lib/rabbitmq","rabbitmqlog:/var/log/rabbitmq" ]
        volume_driver = "local"
        hostname      = "rabbitmq-${var.kontur}"
        ports         = [ "rabbitmq","rabbitmq_ui","rabbitmq_mqtt" ]
        mount {
            type = "bind"
            target = "/etc/rabbitmq/enabled_plugins"
            source = "enabled_plugins"
            readonly = false
            bind_options {
            propagation = "rshared"
            }
        }
        mount {
            type = "bind"
            target = "/etc/rabbitmq/conf.d/10-defaults.conf"
            source = "10-defaults.conf"
            readonly = false
            bind_options {
            propagation = "rshared"
            }
        }
      }

{{ with secret (print "secrets/map/kontur/" $targkontur "/common") }}       
      env {
        RABBITMQ_DEFAULT_USER="{{ .Data.ServiceBus__RabbitMQ__UserName }}"
        RABBITMQ_DEFAULT_PASS="{{ .Data.ServiceBus__RabbitMQ__Password }}"
        RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS="-rabbit log_levels [{connection,error},{default,error}] disk_free_limit 2147483648"
      }
{{ end }}
      service {
        name     = "rabbitmq-${var.kontur}"
        port     = "rabbitmq"
        check {
          name     = "alive"
          type     = "tcp"
          interval = "15s"
          timeout  = "3s"
        }
      }
      
      service {
        name = "rabbitmq-ui-${var.kontur}"
        port = "rabbitmq_ui"
        tags = [
          "traefik.enable=true",
{{ with secret (print "secrets/map/kontur/" $targkontur "/common") }} 
          "traefik.http.routers.rabbitmq-ui-${var.kontur}.rule=(Host(`rmq.{{ .Data.KONTUR_DOMAIN }}`))",
{{ end }}
          "traefik.http.routers.rabbitmq-ui-${var.kontur}.tls=true",
          "traefik.http.routers.rabbitmq-ui-${var.kontur}.entrypoints=websecure",
          "traefik.http.routers.rabbitmq-ui-${var.kontur}.tls.certresolver=lednsci",
          "traefik.http.services.rabbitmq-ui-${var.kontur}.loadbalancer.server.port=${NOMAD_HOST_PORT_rabbitmq_ui}"
        ]
        check {
          name     = "alive"
          type     = "tcp"
          interval = "15s"
          timeout  = "3s"
        }
      }

      service {
        name = "rabbitmq-mqtt-${var.kontur}"
        port = "rabbitmq_mqtt"
        tags = [
          "traefik.enable=true",
{{ with secret (print "secrets/map/kontur/" $targkontur "/common") }} 
          "traefik.tcp.routers.rabbitmq-mqtt-${var.kontur}.rule=(HostSNI(`mqtt.{{ .Data.KONTUR_DOMAIN }}`))",
{{ end }}
          "traefik.tcp.routers.rabbitmq-mqtt-${var.kontur}.tls=true",
          "traefik.tcp.routers.rabbitmq-mqtt-${var.kontur}.entrypoints=mqtt_tls",
          "traefik.tcp.routers.rabbitmq-mqtt-${var.kontur}.tls.certresolver=lednsci",
          "traefik.tcp.services.rabbitmq-mqtt-${var.kontur}.loadbalancer.server.port=${NOMAD_HOST_PORT_rabbitmq_mqtt}"
        ]
        check {
          name     = "alive"
          type     = "tcp"
          interval = "15s"
          timeout  = "3s"
        }
      }

{{ with secret (print "secrets/map/kontur/" $targkontur "/nomad") }}      
      resources {        
        cpu        = {{ .Data.mqttbroker_cpu }}
        memory     = {{ .Data.mqttbroker_memory }}
        memory_max = {{ .Data.mqttbroker_memory_max }}
      }
{{ end }}
    }

    task "map-sensorvalues" {
      driver = "docker"

      template {
        data        = file("./config-kontur/sensorvalues.nomad.tpl")
        destination = "secrets/sensorvalues.env"
        env         = true
      }
      meta {
        version = "${var.version}"
      }

      env {
        ServiceBus__RabbitMQ__Host="${NOMAD_IP_rabbitmq}"
        ServiceBus__RabbitMQ__Port="${NOMAD_HOST_PORT_rabbitmq}"
        ServiceBus__RabbitMQ__HttpPort="${NOMAD_HOST_PORT_rabbitmq_ui}"
      }

      config {
        image      = "${var.sensor_image}"
        ports      = [ "sensor_api","sensor_grpc" ]
        force_pull = "true"
      }
{{ with secret (print "secrets/map/kontur/" $targkontur "/nomad") }} 
      resources {        
        cpu        = {{ .Data.sensorvalues_cpu }}
        memory     = {{ .Data.sensorvalues_memory }}
        memory_max = {{ .Data.sensorvalues_memory_max }}
      }
{{ end }}

      service {
        name = "map-sensorvalues-${var.kontur}"
        port = "sensor_grpc"
        check {
          name            = "alive"
          type            = "grpc"
          port            = "sensor_grpc"
          interval        = "30s"
          timeout         = "3s"
          
           check_restart {
             limit = 10
             grace = "180s"
             ignore_warnings = false
           }
        }
      }
      service {
        name = "map-sensorvalues-api-${var.kontur}"
        port = "sensor_api"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.map-sensorvalues-api-${var.kontur}.rule=(Host(`${KONTUR_DOMAIN}`) && PathPrefix(`/api/devices`))",
          "traefik.http.routers.map-sensorvalues-api-${var.kontur}.middlewares=map-sensorvalues-api-${var.kontur}-strip,body-compress",
          "traefik.http.routers.map-sensorvalues-api-${var.kontur}.tls=true",
          "traefik.http.routers.map-sensorvalues-api-${var.kontur}.entrypoints=websecure",
          "traefik.http.routers.map-sensorvalues-api-${var.kontur}-s.rule=(Host(`${KONTUR_DOMAIN}`) && PathPrefix(`/api/devices/swagger`))",
          "traefik.http.routers.map-sensorvalues-api-${var.kontur}-s.middlewares=map-sensorvalues-api-${var.kontur}-strip,map-sensorvalues-api-${var.kontur}-header,body-compress",
          "traefik.http.routers.map-sensorvalues-api-${var.kontur}-s.tls=true",
          "traefik.http.routers.map-sensorvalues-api-${var.kontur}-s.entrypoints=websecure",
          "traefik.http.services.map-sensorvalues-api-${var.kontur}.loadbalancer.server.port=${NOMAD_HOST_PORT_sensor_api}",
          "traefik.http.middlewares.map-sensorvalues-api-${var.kontur}-strip.stripprefix.prefixes=/api/devices/",
          "traefik.http.middlewares.map-sensorvalues-api-${var.kontur}-strip.stripprefix.forceSlash=false",
          "traefik.http.middlewares.map-sensorvalues-api-${var.kontur}-header.headers.customrequestheaders.X-Forwarded-Prefix=api/devices"
        ]
        check {
          name     = "alive_sensor_api"
          type     = "tcp"
          port     = "sensor_api"
          interval = "30s"
          timeout  = "3s"
        }
        check {
          type     = "http"
          name     = "http_sensor_api"
          path     = "/health"
          interval = "30s"
          timeout  = "5s"
          check_restart {
            limit = 25
            grace = "300s"
            ignore_warnings = false
          }
        }
      }
    }

    task "map-authorization" {
      driver = "docker"

      template {
        data        = file("./config-kontur/authorization.nomad.tpl")
        destination = "secrets/authorization.env"
        env         = true
      }
      meta {
        version = "${var.version}"
      }
      
      env {
        ServiceBus__RabbitMQ__Host="${NOMAD_IP_rabbitmq}"
        ServiceBus__RabbitMQ__Port="${NOMAD_HOST_PORT_rabbitmq}"
        ServiceBus__RabbitMQ__HttpPort="${NOMAD_HOST_PORT_rabbitmq_ui}"
      }

      config {
        image      = "${var.auth_image}"
        force_pull = "true"
        ports      = ["auth_http"]
      }

      service {
        name = "map-authorization-${var.kontur}"
        port = "auth_http"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.map-authorization-${var.kontur}.rule=(Host(`${KONTUR_DOMAIN}`) && PathPrefix(`/api/authorization`))",
          "traefik.http.routers.map-authorization-${var.kontur}.middlewares=map-authorization-${var.kontur}-strip,body-compress",
          "traefik.http.routers.map-authorization-${var.kontur}.tls=true",
          "traefik.http.routers.map-authorization-${var.kontur}.entrypoints=websecure",
          "traefik.http.routers.map-authorization-${var.kontur}-s.rule=(Host(`${KONTUR_DOMAIN}`) && PathPrefix(`/api/authorization/swagger`))",
          "traefik.http.routers.map-authorization-${var.kontur}-s.middlewares=map-authorization-${var.kontur}-strip,map-authorization-${var.kontur}-header,body-compress",
          "traefik.http.routers.map-authorization-${var.kontur}-s.tls=true",
          "traefik.http.routers.map-authorization-${var.kontur}-s.entrypoints=websecure",
          "traefik.http.middlewares.map-authorization-${var.kontur}-strip.stripprefix.prefixes=/api/authorization/",
          "traefik.http.middlewares.map-authorization-${var.kontur}-strip.stripprefix.forceSlash=false",
          "traefik.http.middlewares.map-authorization-${var.kontur}-header.headers.customrequestheaders.X-Forwarded-Prefix=api/authorization"
        ]
        check {
          name     = "alive"
          type     = "tcp"
          port     = "auth_http"
          interval = "15s"
          timeout  = "3s"
        }
        check {
          type     = "http"
          name     = "auth_http"
          path     = "/health"
          interval = "20s"
          timeout  = "5s"
          check_restart {
            limit = 25
            grace = "90s"
            ignore_warnings = false
          }
        } 
      }
{{ with secret (print "secrets/map/kontur/" $targkontur "/nomad") }} 
      resources {        
        cpu        = {{ .Data.authorization_cpu }}
        memory     = {{ .Data.authorization_memory }}
        memory_max = {{ .Data.authorization_memory_max }}
      }
{{ end }}
    }

    task "map-magicairpro" {
      driver = "docker"

      lifecycle {
        hook    = "poststart"
        sidecar = true
      }

      template {
        data        = file("./config-kontur/magicairpro.nomad.tpl")
        destination = "secrets/magicairpro.env"
        env         = true
      }
      meta {
        version = "${var.version}"
      }

      env {
        ServiceBus__RabbitMQ__Host="${NOMAD_IP_rabbitmq}"
        ServiceBus__RabbitMQ__Port="${NOMAD_HOST_PORT_rabbitmq}"
        ServiceBus__RabbitMQ__HttpPort="${NOMAD_HOST_PORT_rabbitmq_ui}"
        SensorValuesClient__Address="http://${NOMAD_ADDR_sensor_grpc}"
        Authorization__Api__Url="http://${NOMAD_ADDR_auth_http}"
      }

      config {
        image      = "${var.map_image}"
        force_pull = "true"
        ports      = ["map_http"]
        volumes    = [ "images/:/app/Resources/images" ]
      }

      service {
        name = "map-magicairpro-${var.kontur}"
        port = "map_http"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.map-magicairpro-${var.kontur}.rule=(Host(`${KONTUR_DOMAIN}`) && PathPrefix(`/api/magicairpro`))",
          "traefik.http.routers.map-magicairpro-${var.kontur}.middlewares=map-magicairpro-${var.kontur}-strip,body-compress",
          "traefik.http.routers.map-magicairpro-${var.kontur}.tls=true",
          "traefik.http.routers.map-magicairpro-${var.kontur}.entrypoints=websecure",
          "traefik.http.routers.map-magicairpro-${var.kontur}-s.rule=(Host(`${KONTUR_DOMAIN}`) && PathPrefix(`/api/magicairpro/swagger`))",
          "traefik.http.routers.map-magicairpro-${var.kontur}-s.middlewares=map-magicairpro-${var.kontur}-strip,map-magicairpro-${var.kontur}-header,body-compress",
          "traefik.http.routers.map-magicairpro-${var.kontur}-s.tls=true",
          "traefik.http.routers.map-magicairpro-${var.kontur}-s.entrypoints=websecure",
          "traefik.http.routers.map-magicairpro-${var.kontur}-h.rule=(Host(`${KONTUR_DOMAIN}`) && PathPrefix(`/api/hangfire/dashboard`))",
          "traefik.http.routers.map-magicairpro-${var.kontur}-h.entrypoints=websecure",
          "traefik.http.routers.map-magicairpro-${var.kontur}-h.middlewares=body-compress",
          "traefik.http.middlewares.map-magicairpro-${var.kontur}-strip.stripprefix.prefixes=/api/magicairpro/",
          "traefik.http.middlewares.map-magicairpro-${var.kontur}-strip.stripprefix.forceSlash=false",
          "traefik.http.middlewares.map-magicairpro-${var.kontur}-header.headers.customrequestheaders.X-Forwarded-Prefix=api/magicairpro"
        ]

        check {
          name     = "alive"
          type     = "tcp"
          port     = "map_http"
          interval = "30s"
          timeout  = "3s"
        }
        check {
          type     = "http"
          name     = "map_http"
          path     = "/health"
          interval = "30s"
          timeout  = "5s"
          check_restart {
            limit = 25
            grace = "300s"
            ignore_warnings = false
          }
        }
      }
{{ with secret (print "secrets/map/kontur/" $targkontur "/nomad") }} 
      resources {        
        cpu        = {{ .Data.magicairpro_cpu }}
        memory     = {{ .Data.magicairpro_memory }}
        memory_max = {{ .Data.magicairpro_memory_max }}
      }
{{ end }}
    }

    task "map-frontend" {
      driver = "docker"

      lifecycle {
        hook    = "poststart"
        sidecar = true
      }

      template {
        data        = file("./config-kontur/frontend.nomad.tpl")
        destination = "secrets/frontend.env"
        env         = true
      }
      meta {
        version     = "${var.version}"
      }

      config {
        image      = "${var.front_image}"
        force_pull = "true"
        ports      = ["front_http"]
      }

      service {
        name = "map-frontend-${var.kontur}"
        port = "front_http"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.map-frontend-${var.kontur}.rule=Host(`${KONTUR_DOMAIN}`)",
          "traefik.http.routers.map-frontend-${var.kontur}.middlewares=body-compress",
          "traefik.http.routers.map-frontend-${var.kontur}.tls=true",
          "traefik.http.routers.map-frontend-${var.kontur}.entrypoints=websecure",
          "traefik.http.routers.map-frontend-${var.kontur}.tls.certresolver=lednsci"
        ]
        check {
          name     = "alive"
          type     = "tcp"
          port     = "front_http"
          interval = "14s"
          timeout  = "3s"
        }
      }
{{ with secret (print "secrets/map/kontur/" $targkontur "/nomad") }}
      resources {        
        cpu        = {{ .Data.frontend_cpu }}
        memory     = {{ .Data.frontend_memory }}
        memory_max = {{ .Data.frontend_memory_max }}
      }
{{ end }}
    }
  }
}
