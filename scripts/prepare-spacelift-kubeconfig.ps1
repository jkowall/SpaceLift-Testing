param(
  [string]$Context = "kind-kind-cluster",
  [string]$ClusterName = "kind-cluster",
  [string]$OutputPath = "$env:USERPROFILE\.kube-spacelift\config"
)

$ErrorActionPreference = "Stop"

$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

$server = "https://$ClusterName-control-plane:6443"
$rawConfig = (kubectl config view --minify --raw --context=$Context) -join [Environment]::NewLine
$rewrittenConfig = $rawConfig -replace 'server:\s+https://[^\r\n]+', "server: $server"

Set-Content -Path $OutputPath -Value $rewrittenConfig -Encoding ascii

Write-Host "Wrote kubeconfig for Spacelift runs:"
Write-Host "  $OutputPath"
Write-Host "Server:"
Write-Host "  $server"
Write-Host ""
Write-Host "Upload this file to the Spacelift stack mounted file path:"
Write-Host "  kube/config"
Write-Host ""
Write-Host "Set this stack environment variable:"
Write-Host "  TF_VAR_kubeconfig_path=/mnt/workspace/kube/config"
