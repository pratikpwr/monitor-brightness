<#
  web-install.ps1 - one-line installer for Monitor Brightness. Run in PowerShell:

      irm https://raw.githubusercontent.com/pratikpwr/monitor-brightness/main/web-install.ps1 | iex

  Downloads the latest release ZIP from GitHub, runs its installer, and cleans up.
#>
& {
    $ErrorActionPreference = 'Stop'
    $url = 'https://github.com/pratikpwr/monitor-brightness/releases/latest/download/MonitorBrightness.zip'
    $tmp = Join-Path $env:TEMP ('MonitorBrightness-' + [guid]::NewGuid().ToString('N'))
    $zip = "$tmp.zip"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Write-Host 'Downloading Monitor Brightness...'
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        $installer = Get-ChildItem $tmp -Recurse -Filter install.ps1 | Select-Object -First 1
        if (-not $installer) { throw 'install.ps1 not found in the downloaded ZIP.' }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer.FullName
        if ($LASTEXITCODE) { throw "Installer exited with code $LASTEXITCODE." }
    }
    catch { Write-Host "Install failed: $_" -ForegroundColor Red }
    finally { Remove-Item $zip, $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
