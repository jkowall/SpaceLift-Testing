# ---------------------------------------------------------------------------
# HotROD — demo ride-hailing app that generates realistic distributed traces
# ---------------------------------------------------------------------------

locals {
  hotrod_labels = {
    app                            = "hotrod"
    "app.kubernetes.io/name"       = "hotrod"
    "app.kubernetes.io/component"  = "demo"
    "app.kubernetes.io/managed-by" = "opentofu"
  }

  # DNS name of the Jaeger OTLP ClusterIP service
  jaeger_otlp_host = "jaeger-otlp.${kubernetes_namespace.observability.metadata[0].name}.svc.cluster.local"
}

resource "kubernetes_deployment" "hotrod" {
  metadata {
    name      = "hotrod"
    namespace = kubernetes_namespace.observability.metadata[0].name
    labels    = local.hotrod_labels
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "hotrod"
      }
    }

    template {
      metadata {
        labels = local.hotrod_labels
      }

      spec {
        container {
          name  = "hotrod"
          # NOTE: `latest` is used here as requested. For production deployments,
          # pin to a specific version (e.g. jaegertracing/example-hotrod:1.52.0).
          image             = "jaegertracing/example-hotrod:latest"
          image_pull_policy = "Always"

          port {
            name           = "web"
            container_port = 8080
            protocol       = "TCP"
          }

          # Point HotROD at the Jaeger OTLP HTTP collector.
          env {
            name  = "OTEL_EXPORTER_OTLP_ENDPOINT"
            value = "http://${local.jaeger_otlp_host}:4318"
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "128Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds        = 15
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }
      }
    }
  }

  # Ensure Jaeger is deployed before HotROD tries to send traces
  depends_on = [
    kubernetes_deployment.jaeger,
    kubernetes_service.jaeger_otlp,
  ]
}

# ---------------------------------------------------------------------------
# NodePort service — exposes the HotROD UI to the local machine
# ---------------------------------------------------------------------------

resource "kubernetes_service" "hotrod" {
  metadata {
    name      = "hotrod"
    namespace = kubernetes_namespace.observability.metadata[0].name
    labels    = local.hotrod_labels
  }

  spec {
    selector = {
      app = "hotrod"
    }

    type = "NodePort"

    port {
      name        = "web"
      port        = 8080
      target_port = 8080
      node_port   = 30808
      protocol    = "TCP"
    }
  }
}
