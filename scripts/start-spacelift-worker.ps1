param(
  [string]$TokenFile = ".\spacelift.config",
  [string]$PrivateKeyFile = ".\spacelift.key",
  [string]$KubeconfigDirectory = "$env:USERPROFILE\.kube-spacelift",
  [string]$ContainerName = "spacelift-worker",
  [string]$WorkerNetwork = "kind"
)

$ErrorActionPreference = "Stop"

function Convert-ToPodmanMachinePath {
  param([string]$Path)

  $resolved = (Resolve-Path $Path).Path
  if ($resolved -match '^([A-Za-z]):\\(.*)$') {
    $drive = $matches[1].ToLowerInvariant()
    $tail = $matches[2] -replace '\\', '/'
    return "/mnt/$drive/$tail"
  }

  return $resolved -replace '\\', '/'
}

$spaceliftToken = (Get-Content $TokenFile -Raw).Trim()
$privateKeyContainerPath = (Resolve-Path -Relative $PrivateKeyFile) -replace '\\', '/'
$spaceliftPrivateKey = podman run --rm -v "${PWD}:/w" -w /w alpine base64 -w0 $privateKeyContainerPath
$podmanSocket = (podman info --format '{{.Host.RemoteSocket.Path}}').Trim() -replace '^unix://',''
$kubeconfigMountSource = Convert-ToPodmanMachinePath $KubeconfigDirectory
$extraMounts = "${kubeconfigMountSource}:/home/spacelift/.kube"

podman machine ssh 'sudo mkdir -p /opt/spacelift && sudo chown -R $(id -u):$(id -g) /opt/spacelift' | Out-Null
podman rm -f $ContainerName 2>$null | Out-Null

podman run -d `
  --name $ContainerName `
  --network $WorkerNetwork `
  -e SPACELIFT_TOKEN="$spaceliftToken" `
  -e SPACELIFT_POOL_PRIVATE_KEY="$spaceliftPrivateKey" `
  -e SPACELIFT_WORKER_NETWORK="$WorkerNetwork" `
  -e SPACELIFT_WORKER_EXTRA_MOUNTS="$extraMounts" `
  -e SPACELIFT_WORKER_RO_EXTRA_MOUNTS="$extraMounts" `
  -e SPACELIFT_WORKER_WO_EXTRA_MOUNTS="$extraMounts" `
  -v "/opt/spacelift:/opt/spacelift" `
  -v "${KubeconfigDirectory}:/home/spacelift/.kube:ro" `
  -v "${KubeconfigDirectory}:${kubeconfigMountSource}:ro" `
  -v "${podmanSocket}:/var/run/docker.sock" `
  public.ecr.aws/spacelift/launcher:latest

Start-Sleep -Seconds 5
podman ps --filter "name=$ContainerName" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
podman logs --tail 30 $ContainerName
