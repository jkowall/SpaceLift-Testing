@{
  # Files generated/downloaded when creating the Spacelift private worker pool.
  TokenFile      = ".\spacelift.config"
  PrivateKeyFile = ".\spacelift.key"

  # Local Kubernetes/kind settings.
  KubeconfigDirectory = "~\.kube-spacelift"
  KubeconfigContext   = "kind-kind-cluster"
  KindClusterName     = "kind-cluster"
  WorkerNetwork       = "kind"

  # Local container name for the Spacelift launcher.
  ContainerName = "spacelift-worker"
}
