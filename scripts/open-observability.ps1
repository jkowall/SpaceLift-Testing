$ErrorActionPreference = "Stop"

$namespace = "observability"
$forwards = @(
  @{
    Name      = "HotROD"
    Arguments = @("-n", $namespace, "port-forward", "svc/hotrod", "8080:8080")
    Url       = "http://localhost:8080"
  },
  @{
    Name      = "Jaeger"
    Arguments = @("-n", $namespace, "port-forward", "svc/jaeger-ui", "16686:16686")
    Url       = "http://localhost:16686"
  }
)

Write-Host "Starting local port-forwards. Close the opened PowerShell windows to stop them."

foreach ($forward in $forwards) {
  Start-Process powershell.exe -ArgumentList @(
    "-NoExit",
    "-Command",
    "kubectl $($forward.Arguments -join ' ')"
  ) | Out-Null

  Write-Host "$($forward.Name): $($forward.Url)"
}
