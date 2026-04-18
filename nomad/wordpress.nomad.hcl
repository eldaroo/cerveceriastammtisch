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

variable "wp_home" {
  type    = string
  default = "https://cerveceriastammtisch.com.ar"
}

variable "wp_siteurl" {
  type    = string
  default = "https://cerveceriastammtisch.com.ar"
}

variable "wp_table_prefix" {
  type    = string
  default = "wp_"
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
        memory = 768
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
WORDPRESS_DB_HOST={{ env "NOMAD_ADDR_db" }}
WORDPRESS_DB_NAME=${var.db_name}
WORDPRESS_DB_USER=${var.db_user}
WORDPRESS_DB_PASSWORD=${var.db_password}
WORDPRESS_TABLE_PREFIX=${var.wp_table_prefix}
WORDPRESS_CONFIG_EXTRA=define( 'WP_HOME', '${var.wp_home}' ); define( 'WP_SITEURL', '${var.wp_siteurl}' ); if ( isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https' ) { $_SERVER['HTTPS'] = 'on'; }
EOF
      }

      resources {
        cpu    = 700
        memory = 768
      }

      service {
        name = var.app_name
        port = "http"

        check {
          type     = "tcp"
          interval = "15s"
          timeout  = "5s"
        }
      }
    }
  }
}
