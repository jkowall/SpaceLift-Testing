param(
  [string]$ConfigFile = ".\local.spacelift-worker.psd1"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ConfigFile)) {
  throw "Missing $ConfigFile. Copy local.spacelift-worker.example.psd1 to local.spacelift-worker.psd1 and edit it for this machine."
}

$config = Import-PowerShellDataFile $ConfigFile
$kubeconfigDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($config.KubeconfigDirectory)

foreach ($requiredPath in @($config.TokenFile, $config.PrivateKeyFile)) {
  if (-not (Test-Path $requiredPath)) {
    throw "Missing required file: $requiredPath"
  }
}

.\scripts\prepare-spacelift-kubeconfig.ps1 `
  -Context $config.KubeconfigContext `
  -ClusterName $config.KindClusterName `
  -OutputPath (Join-Path $kubeconfigDirectory "config")

.\scripts\start-spacelift-worker.ps1 `
  -TokenFile $config.TokenFile `
  -PrivateKeyFile $config.PrivateKeyFile `
  -KubeconfigDirectory $kubeconfigDirectory `
  -ContainerName $config.ContainerName `
  -WorkerNetwork $config.WorkerNetwork
