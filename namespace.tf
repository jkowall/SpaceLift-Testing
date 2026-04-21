resource "kubernetes_namespace" "observability" {
  metadata {
    name = "observability"

    labels = {
      "app.kubernetes.io/managed-by" = "opentofu"
      "app.kubernetes.io/part-of"    = "observability-sandbox"
    }
  }
}
