<#
.SCRIPT ACTIONS
 determine if om cli is installed, if it is not, download it from here: https://github.com/pivotal-cf/om/releases/download/7.18.2/om-windows-amd64-7.18.2.exe
 make sure to rename it to om.exe and put it in your PATH

 download the env file: https://fileshare.tnz-field-epc.lvn.broadcom.net/config/env/env.yml
 download the config-srt-otel-template: https://fileshare.tnz-field-epc.lvn.broadcom.net/config/srt/srt-otel-template.yml

 use om cli to determine if '$HubCollectorProductName' product is installed, is so it'll be included in these results:
    om --env env/env.yml products /d /format:json
#>

param(
    [string]$HubCollectorProductName = "hub-tas-collector",
    [string]$ClientName = "hub-tas-collector",
    [string]$ClientSecret = "hub-tas-collector",
    [string]$OmCliDownloadUrl = "https://github.com/pivotal-cf/om/releases/download/7.18.2/om-windows-amd64-7.18.2.exe",
    [string]$EnvFileUrl = "https://fileshare.tnz-field-epc.lvn.broadcom.net/config/env/env.yml",
    [string]$ConfigSrtOtelTemplateUrl = "https://fileshare.tnz-field-epc.lvn.broadcom.net/config/srt/srt-otel-template.yml"
)

function Ensure-OmCli {
    $omPath = (Get-Command om.exe -ErrorAction SilentlyContinue)?.Source
    if (-not $omPath) {
        Write-Host "om CLI not found. Downloading..."
        $targetPath = "$PSScriptRoot\om.exe"
        Invoke-WebRequest -Uri $OmCliDownloadUrl -OutFile $targetPath
        Write-Host "Downloaded om CLI to $targetPath"
        $env:PATH += ";$PSScriptRoot"
    } else {
        Write-Host "om CLI found at $omPath"
    }
}

function Download-EnvFile {
    $envTarget = "env\env.yml"
    if (-not (Test-Path "env")) { New-Item -ItemType Directory -Path "env" | Out-Null }
    Write-Host "Downloading env file..."
    Invoke-WebRequest -Uri $EnvFileUrl -OutFile $envTarget
    Write-Host "Downloaded env file to $envTarget"
}

function Download-ConfigSrtOtelTemplate {
    $configTarget = "config-srt-otel-template.yml"
    Write-Host "Downloading config-srt-otel-template..."
    Invoke-WebRequest -Uri $ConfigSrtOtelTemplateUrl -OutFile $configTarget
    Write-Host "Downloaded config-srt-otel-template to $configTarget"
}

function Check-HubCollectorProduct {
    $envFile = "env\env.yml"
    if (-not (Test-Path $envFile)) {
        Write-Error "env file not found at $envFile"
        return
    }
    Write-Host "Checking installed products with om CLI..."
    $productsJson = & om.exe --env $envFile products --format json 2>$null
    if (-not $productsJson) {
        Write-Error "Failed to get products from om CLI."
        return
    }
    $products = $productsJson | ConvertFrom-Json
    $found = $products | Where-Object { $_.name -eq $HubCollectorProductName }
    if ($found) {
        Write-Host "Product '$HubCollectorProductName' is installed."
    } else {
        Write-Host "Product '$HubCollectorProductName' is NOT installed."
    }
}

function Reconfigure-CFWithHubTasCollectorValues {
    param (
        [string]$EnvFile = "env\env.yml",
        [string]$ProductName = $HubCollectorProductName,
        [string]$ConfigTemplate = "config-srt-otel-template.yml"
    )

    $filename = "cf-otel-config.yml"
    if (-not (Test-Path $filename)) { New-Item -ItemType File -Path $filename | Out-Null }

    Write-Host "Extracting certificate values from Ops Manager..."

    # Helper to indent PEM content
    function Indent-Content($content) {
        return ($content -split "`n" | ForEach-Object { "  $_" }) -join "`n"
    }

    # opsman-ca
    $ca_pem = & om.exe --env $EnvFile certificate-authority --cert-pem
    Add-Content -Path $filename -Value "opsman-ca: |"
    Add-Content -Path $filename -Value (Indent-Content $ca_pem)

    # collector-cert-pem
    $cert_pem = & om.exe --env $EnvFile credentials -p $ProductName -c .hub_tas_agent.open_telemetry_agent_mtls -t json -f cert_pem
    Add-Content -Path $filename -Value "collector-cert-pem: |"
    Add-Content -Path $filename -Value (Indent-Content $cert_pem)

    # collector-private-key-pem
    $private_key_pem = & om.exe --env $EnvFile credentials -p $ProductName -c .hub_tas_agent.open_telemetry_agent_mtls -t json -f private_key_pem
    Add-Content -Path $filename -Value "collector-private-key-pem: |"
    Add-Content -Path $filename -Value (Indent-Content $private_key_pem)

    # syslog-cert-pem
    $syslog_cert_pem = & om.exe --env $EnvFile credentials -p $ProductName -c .properties.syslog_mtls -t json -f cert_pem
    Add-Content -Path $filename -Value "syslog-cert-pem: |"
    Add-Content -Path $filename -Value (Indent-Content $syslog_cert_pem)

    # syslog-private-key-pem
    $syslog_private_key_pem = & om.exe --env $EnvFile credentials -p $ProductName -c .properties.syslog_mtls -t json -f private_key_pem
    Add-Content -Path $filename -Value "syslog-private-key-pem: |"
    Add-Content -Path $filename -Value (Indent-Content $syslog_private_key_pem)

    Write-Host "Updating CF/SRT configuration using om CLI..."
    & om.exe --env $EnvFile configure-product -p cf -c "$ConfigTemplate" -l $filename
}

# Main execution
Ensure-OmCli
Download-EnvFile
Download-ConfigSrtOtelTemplate
Check-HubCollectorProduct

# Only run reconfiguration if product is installed
$envFile = "env\env.yml"
$productsJson = & om.exe --env $envFile products --format json 2>$null
$products = $productsJson | ConvertFrom-Json
$found = $products | Where-Object { $_.name -eq $HubCollectorProductName }
if ($found) {
    Reconfigure-CFWithHubTasCollectorValues -EnvFile $envFile -ProductName $HubCollectorProductName -ConfigTemplate "config-srt-otel-template.yml"
}




