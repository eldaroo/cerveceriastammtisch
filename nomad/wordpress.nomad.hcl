variable "datacenter" {
  type    = string
  default = "dc1"
}

variable "namespace" {
  type    = string
  default = "default"
}

variable "app_name" {
  type    = string
  default = "cerveceria-stammtisch"
}

variable "wordpress_image" {
  type    = string
  default = "ghcr.io/eldaroo/cerveceriastammtisch-wordpress:latest"
}

variable "mariadb_image" {
  type    = string
  default = "ghcr.io/eldaroo/cerveceriastammtisch-mariadb:latest"
}

variable "registry_username" {
  type    = string
  default = ""
}

variable "registry_password" {
  type    = string
  default = ""
}

variable "db_name" {
  type    = string
  default = "cerveceria"
}

variable "db_user" {
  type    = string
  default = "cerveceria_wp"
}

variable "db_password" {
  type = string
}

variable "wp_table_prefix" {
  type    = string
  default = "wp_"
}

variable "domain" {
  type    = string
  default = "cerveceriastammtisch.com.ar"
}

job "cerveceria-stammtisch" {
  datacenters = [var.datacenter]
  namespace   = var.namespace
  type        = "service"

  group "cms" {
    count = 1

    restart {
      attempts = 10
      interval = "30m"
      delay    = "15s"
      mode     = "delay"
    }

    network {
      mode = "bridge"

      port "http" {
        to = 80
      }

      port "db" {
        to = 3306
      }
    }

    task "db" {
      driver = "docker"

      config {
        image = var.mariadb_image
        auth {
          username = var.registry_username
          password = var.registry_password
        }
        ports = ["db"]
        mount {
          type   = "volume"
          target = "/var/lib/mysql"
          source = "cerveceria_db_data"

          volume_options {
            driver_config {
              name = "local"
            }
          }
        }
      }

      env {
        MARIADB_DATABASE             = var.db_name
        MARIADB_USER                 = var.db_user
        MARIADB_PASSWORD             = var.db_password
        MARIADB_RANDOM_ROOT_PASSWORD = "1"
      }

      resources {
        cpu    = 500
        memory = 128
      }

      service {
        name = "${var.app_name}-db"
        port = "db"

        check {
          type     = "tcp"
          interval = "15s"
          timeout  = "3s"
        }
      }
    }

    task "wordpress" {
      driver = "docker"

      config {
        image = var.wordpress_image
        auth {
          username = var.registry_username
          password = var.registry_password
        }
        ports = ["http"]
      }

      template {
        destination = "secrets/wordpress.env"
        env         = true
data        = <<EOF
WORDPRESS_DB_HOST={{ printf "127.0.0.1:%s" (env "NOMAD_PORT_db") | toJSON }}
WORDPRESS_DB_NAME=${jsonencode(var.db_name)}
WORDPRESS_DB_USER=${jsonencode(var.db_user)}
WORDPRESS_DB_PASSWORD=${jsonencode(var.db_password)}
WORDPRESS_TABLE_PREFIX=${jsonencode(var.wp_table_prefix)}
EOF
      }

      resources {
        cpu    = 700
        memory = 128
      }

      service {
        name = var.app_name
        port = "http"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.${var.app_name}.rule=Host(`${var.domain}`) || Host(`www.${var.domain}`)",
          "traefik.http.routers.${var.app_name}.entrypoints=websecure",
          "traefik.http.routers.${var.app_name}.tls.certresolver=le",
        ]

        check {
          type     = "tcp"
          interval = "15s"
          timeout  = "5s"
        }
      }
    }
  }
}
