# Kubernetes Module - Deploys Matrix Synapse and Element Web
# Best Practice: Use namespaces to isolate applications
# Best Practice: Fetch secrets from AWS SSM Parameter Store instead of hardcoding
# Deviation: Using simple deployments instead of Helm charts for transparency

# Data sources to fetch secrets from SSM Parameter Store
data "aws_ssm_parameter" "postgres_password" {
  name = var.postgres_password_parameter
}

data "aws_ssm_parameter" "postgres_user" {
  name = var.postgres_user_parameter
}

data "aws_ssm_parameter" "postgres_db" {
  name = var.postgres_db_parameter
}

data "aws_ssm_parameter" "synapse_server_name" {
  name = var.synapse_server_name_parameter
}

data "aws_ssm_parameter" "synapse_registration_secret" {
  name = var.synapse_registration_secret_parameter
}

data "aws_ssm_parameter" "synapse_macaroon_secret" {
  name = var.synapse_macaroon_secret_parameter
}

# Create namespace for Matrix applications
resource "kubernetes_namespace" "matrix" {
  metadata {
    name = var.namespace
    labels = {
      name = var.namespace
    }
  }
}

# PostgreSQL Database for Synapse
# Best Practice: Use managed database (RDS) in production
# Deviation: Running PostgreSQL in-cluster for simplicity and cost
resource "kubernetes_deployment" "postgres" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace.matrix.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "postgres"
      }
    }

    template {
      metadata {
        labels = {
          app = "postgres"
        }
      }

      spec {
        container {
          name  = "postgres"
          image = "postgres:15-alpine"

          env {
            name  = "POSTGRES_DB"
            value = data.aws_ssm_parameter.postgres_db.value
          }

          env {
            name  = "POSTGRES_USER"
            value = data.aws_ssm_parameter.postgres_user.value
          }

          env {
            name  = "POSTGRES_PASSWORD"
            value = data.aws_ssm_parameter.postgres_password.value # Best Practice: Fetched from SSM
          }

          env {
            name  = "POSTGRES_INITDB_ARGS"
            value = "--locale=C --encoding=UTF8"
          }

          port {
            container_port = 5432
          }

          # Resource limits to prevent OOM on t3.small instances
          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          volume_mount {
            name       = "postgres-storage"
            mount_path = "/var/lib/postgresql/data"
          }
        }

        volume {
          name = "postgres-storage"
          empty_dir {} # Deviation: Use PersistentVolume with EBS in production
        }
      }
    }
  }
}

resource "kubernetes_service" "postgres" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace.matrix.metadata[0].name
  }

  spec {
    selector = {
      app = "postgres"
    }

    port {
      port        = 5432
      target_port = 5432
    }

    type = "ClusterIP"
  }
}

# Synapse configuration file
resource "kubernetes_config_map" "synapse_config" {
  metadata {
    name      = "synapse-config"
    namespace = kubernetes_namespace.matrix.metadata[0].name
  }

  data = {
    "homeserver.yaml" = <<-EOT
server_name: "${data.aws_ssm_parameter.synapse_server_name.value}"
pid_file: /data/homeserver.pid
listeners:
  - port: 8008
    tls: false
    type: http
    x_forwarded: true
    resources:
      - names: [client, federation]
        compress: false

database:
  name: psycopg2
  args:
    user: ${data.aws_ssm_parameter.postgres_user.value}
    password: ${data.aws_ssm_parameter.postgres_password.value}
    database: ${data.aws_ssm_parameter.postgres_db.value}
    host: postgres
    port: 5432
    cp_min: 5
    cp_max: 10

log_config: "/data/log.config"

media_store_path: /data/media_store
signing_key_path: /data/signing.key
trusted_key_servers:
  - server_name: "matrix.org"
suppress_key_server_warning: true

registration_shared_secret: "${data.aws_ssm_parameter.synapse_registration_secret.value}"
macaroon_secret_key: "${data.aws_ssm_parameter.synapse_macaroon_secret.value}"
form_secret: "${data.aws_ssm_parameter.synapse_macaroon_secret.value}"

report_stats: false
enable_registration: false
enable_registration_without_verification: false
    EOT

    "log.config" = <<-EOT
version: 1
formatters:
  precise:
    format: '%(asctime)s - %(name)s - %(lineno)d - %(levelname)s - %(message)s'
handlers:
  console:
    class: logging.StreamHandler
    formatter: precise
root:
  level: INFO
  handlers: [console]
disable_existing_loggers: false
    EOT
  }
}

# Matrix Synapse Homeserver
resource "kubernetes_deployment" "synapse" {
  metadata {
    name      = "synapse"
    namespace = kubernetes_namespace.matrix.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "synapse"
      }
    }

    template {
      metadata {
        labels = {
          app = "synapse"
        }
      }

      spec {
        # Wait for PostgreSQL to be ready and set up config
        init_container {
          name  = "wait-for-postgres"
          image = "busybox:1.36"
          command = [
            "sh",
            "-c",
            "until nc -z postgres 5432; do echo waiting for postgres; sleep 2; done"
          ]
        }

        # Generate signing key if it doesn't exist
        init_container {
          name  = "generate-signing-key"
          image = "matrixdotorg/synapse:latest"

          security_context {
            run_as_user = 0 # Run as root to set permissions
          }

          command = [
            "sh",
            "-c",
            <<-EOT
            cp /config/homeserver.yaml /data/homeserver.yaml
            cp /config/log.config /data/log.config
            if [ ! -f /data/signing.key ]; then
              python -m synapse.app.homeserver --config-path /data/homeserver.yaml --generate-keys
            fi
            mkdir -p /data/media_store
            chown -R 991:991 /data
            EOT
          ]
          volume_mount {
            name       = "synapse-config"
            mount_path = "/config"
            read_only  = true
          }
          volume_mount {
            name       = "synapse-data"
            mount_path = "/data"
          }
        }

        container {
          name  = "synapse"
          image = "matrixdotorg/synapse:latest"

          args = [
            "run",
            "--config-path=/data/homeserver.yaml"
          ]

          port {
            container_port = 8008
            name           = "http"
          }

          volume_mount {
            name       = "synapse-data"
            mount_path = "/data"
          }

          # Synapse needs ~1GB RAM minimum
          resources {
            requests = {
              cpu    = "250m"
              memory = "768Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
          }

          # Health checks
          liveness_probe {
            http_get {
              path = "/_matrix/client/versions"
              port = 8008
            }
            initial_delay_seconds = 60
            period_seconds        = 30
          }

          readiness_probe {
            http_get {
              path = "/_matrix/client/versions"
              port = 8008
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }
        }

        volume {
          name = "synapse-config"
          config_map {
            name = kubernetes_config_map.synapse_config.metadata[0].name
          }
        }

        volume {
          name = "synapse-data"
          empty_dir {} # Deviation: Use PersistentVolume with EBS in production
        }
      }
    }
  }

  depends_on = [kubernetes_deployment.postgres, kubernetes_config_map.synapse_config]
}

resource "kubernetes_service" "synapse" {
  metadata {
    name      = "synapse"
    namespace = kubernetes_namespace.matrix.metadata[0].name
  }

  spec {
    selector = {
      app = "synapse"
    }

    port {
      port        = 8008
      target_port = 8008
      name        = "http"
    }

    type = "LoadBalancer" # Creates AWS ELB for external access
  }
}

# Element Web Client
resource "kubernetes_deployment" "element" {
  metadata {
    name      = "element"
    namespace = kubernetes_namespace.matrix.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "element"
      }
    }

    template {
      metadata {
        labels = {
          app = "element"
        }
      }

      spec {
        container {
          name  = "element"
          image = "vectorim/element-web:latest"

          port {
            container_port = 80
            name           = "http"
          }

          # Element is lightweight
          resources {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }

          # Health checks
          liveness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 30
            period_seconds        = 30
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "element" {
  metadata {
    name      = "element"
    namespace = kubernetes_namespace.matrix.metadata[0].name
  }

  spec {
    selector = {
      app = "element"
    }

    port {
      port        = 80
      target_port = 80
      name        = "http"
    }

    type = "LoadBalancer" # Creates AWS ELB for external access
  }
}
