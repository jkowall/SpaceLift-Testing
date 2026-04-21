# ---------------------------------------------------------------------------
# Jaeger all-in-one — collects, stores and visualises traces
# ---------------------------------------------------------------------------

locals {
  jaeger_labels = {
    app                            = "jaeger"
    "app.kubernetes.io/name"       = "jaeger"
    "app.kubernetes.io/component"  = "tracing"
    "app.kubernetes.io/managed-by" = "opentofu"
  }
}

resource "kubernetes_deployment" "jaeger" {
  metadata {
    name      = "jaeger"
    namespace = kubernetes_namespace.observability.metadata[0].name
    labels    = local.jaeger_labels
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "jaeger"
      }
    }

    template {
      metadata {
        labels = local.jaeger_labels
      }

      spec {
        container {
          name  = "jaeger"
          # NOTE: `latest` is used here as requested. For production deployments,
          # pin to a specific version (e.g. jaegertracing/all-in-one:1.52.0).
          image             = "jaegertracing/all-in-one:latest"
          image_pull_policy = "Always"

          # Collector / OTLP ports
          port {
            name           = "otlp-grpc"
            container_port = 4317
            protocol       = "TCP"
          }
          port {
            name           = "otlp-http"
            container_port = 4318
            protocol       = "TCP"
          }

          # Jaeger UI
          port {
            name           = "ui"
            container_port = 16686
            protocol       = "TCP"
          }

          # Query gRPC (used internally by the UI)
          port {
            name           = "grpc-query"
            container_port = 16685
            protocol       = "TCP"
          }

          env {
            name  = "COLLECTOR_OTLP_ENABLED"
            value = "true"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 16686
            }
            initial_delay_seconds = 10
            period_seconds        = 15
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 16686
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# ClusterIP service — OTLP endpoints consumed by in-cluster workloads
# ---------------------------------------------------------------------------

resource "kubernetes_service" "jaeger_otlp" {
  metadata {
    name      = "jaeger-otlp"
    namespace = kubernetes_namespace.observability.metadata[0].name
    labels    = local.jaeger_labels
  }

  spec {
    selector = {
      app = "jaeger"
    }

    type = "ClusterIP"

    port {
      name        = "otlp-grpc"
      port        = 4317
      target_port = 4317
      protocol    = "TCP"
    }

    port {
      name        = "otlp-http"
      port        = 4318
      target_port = 4318
      protocol    = "TCP"
    }
  }
}

# ---------------------------------------------------------------------------
# NodePort service — exposes the Jaeger UI to the local machine
# ---------------------------------------------------------------------------

resource "kubernetes_service" "jaeger_ui" {
  metadata {
    name      = "jaeger-ui"
    namespace = kubernetes_namespace.observability.metadata[0].name
    labels    = local.jaeger_labels
  }

  spec {
    selector = {
      app = "jaeger"
    }

    type = "NodePort"

    port {
      name        = "ui"
      port        = 16686
      target_port = 16686
      node_port   = 30686
      protocol    = "TCP"
    }
  }
}
