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
  default = "wordpress:php8.2-apache"
}

variable "mariadb_image" {
  type    = string
  default = "mariadb:10.11"
}

variable "db_name" {
  type = string
}

variable "db_user" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "wp_home" {
  type = string
}

variable "wp_siteurl" {
  type = string
}

variable "wp_table_prefix" {
  type    = string
  default = "wp_"
}

variable "wp_content_volume" {
  type    = string
  default = "cerveceria_wp_content"
}

variable "db_data_volume" {
  type    = string
  default = "cerveceria_db_data"
}

variable "db_init_volume" {
  type    = string
  default = "cerveceria_db_init"
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

    volume "wp_content" {
      type      = "host"
      source    = var.wp_content_volume
      read_only = false
    }

    volume "db_data" {
      type      = "host"
      source    = var.db_data_volume
      read_only = false
    }

    volume "db_init" {
      type      = "host"
      source    = var.db_init_volume
      read_only = true
    }

    task "db" {
      driver = "docker"

      config {
        image = var.mariadb_image
        ports = ["db"]
      }

      env {
        MARIADB_DATABASE             = var.db_name
        MARIADB_USER                 = var.db_user
        MARIADB_PASSWORD             = var.db_password
        MARIADB_RANDOM_ROOT_PASSWORD = "1"
      }

      volume_mount {
        volume      = "db_data"
        destination = "/var/lib/mysql"
        read_only   = false
      }

      volume_mount {
        volume      = "db_init"
        destination = "/docker-entrypoint-initdb.d"
        read_only   = true
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

      volume_mount {
        volume      = "wp_content"
        destination = "/var/www/html/wp-content"
        read_only   = false
      }

      resources {
        cpu    = 700
        memory = 768
      }

      service {
        name = var.app_name
        port = "http"

        check {
          type     = "http"
          path     = "/"
          interval = "15s"
          timeout  = "5s"
        }
      }
    }
  }
}
