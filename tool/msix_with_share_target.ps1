param(
  [string]$Architecture = "x64"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Add-ShareTargetToManifest([string]$ManifestPath) {
  $xml = Get-Content $ManifestPath -Raw
  if ($xml -match "windows\\.shareTarget") {
    Write-Host "Share target already present in AppxManifest.xml"
    return
  }

  $shareExt = @"
  <uap:Extension Category="windows.shareTarget">
    <uap:ShareTarget>
      <uap:SupportedFileTypes>
        <uap:SupportsAnyFileType />
      </uap:SupportedFileTypes>
    </uap:ShareTarget>
  </uap:Extension>
"@

  if ($xml -match "<Extensions>") {
    $xml = $xml -replace "<Extensions>", "<Extensions>`r`n      $shareExt"
  } else {
    $xml = $xml -replace "</Application>", "        <Extensions>`r`n      $shareExt`r`n        </Extensions>`r`n      </Application>"
  }

  Set-Content -Path $ManifestPath -Value $xml -Encoding UTF8
  Write-Host "Added ShareTarget extension to AppxManifest.xml"
}

function Add-NetworkCapabilitiesToManifest([string]$ManifestPath) {
  $xml = Get-Content $ManifestPath -Raw
  $changed = $false

  if ($xml -notmatch "<Capability\s+Name=`"internetClient`"\s*/>") {
    $xml = $xml -replace "</Capabilities>", "    <Capability Name=`"internetClient`" />`r`n  </Capabilities>"
    $changed = $true
  }

  if ($xml -notmatch "<Capability\s+Name=`"internetClientServer`"\s*/>") {
    $xml = $xml -replace "</Capabilities>", "    <Capability Name=`"internetClientServer`" />`r`n  </Capabilities>"
    $changed = $true
  }

  if ($xml -notmatch "<Capability\s+Name=`"privateNetworkClientServer`"\s*/>") {
    $xml = $xml -replace "</Capabilities>", "    <Capability Name=`"privateNetworkClientServer`" />`r`n  </Capabilities>"
    $changed = $true
  }

  if ($changed) {
    Set-Content -Path $ManifestPath -Value $xml -Encoding UTF8
    Write-Host "Added network server capabilities to AppxManifest.xml"
  } else {
    Write-Host "Network server capabilities already present in AppxManifest.xml"
  }
}

Write-Host "Building unpackaged MSIX files..."
dart run msix:build --architecture $Architecture

$manifests = @(
  Get-ChildItem -Path "build\\windows" -Recurse -Include "AppxManifest*.xml" -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending
)

if (-not $manifests -or $manifests.Count -eq 0) {
  throw "AppxManifest.xml not found under build\\windows. Run `flutter build windows` once and retry."
}

$manifest = $manifests[0].FullName
Write-Host "Patching manifest: $manifest"
Add-NetworkCapabilitiesToManifest -ManifestPath $manifest
Add-ShareTargetToManifest -ManifestPath $manifest

Write-Host "Packing MSIX..."
dart run msix:pack --architecture $Architecture
