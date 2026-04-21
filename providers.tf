terraform {
  required_version = ">= 1.6.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
  }
}

provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig_path)
  config_context = var.kubeconfig_context
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file used to authenticate with the cluster. Supports ~ expansion."
  type        = string
  default     = "~/.kube/config"
}

variable "kubeconfig_context" {
  description = "Kubeconfig context to use. Leave empty to use the current-context."
  type        = string
  default     = ""
}
