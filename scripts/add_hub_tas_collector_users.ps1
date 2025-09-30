<#
.SYNOPSIS
    PowerShell script to add a UAA client for the Hub Collector to both BOSH Director and Opsman UAAs via SSH.

.DESCRIPTION
    This script automates the process of adding or updating a UAA client for the Hub Collector in both BOSH Director and Opsman UAAs.
    It connects to the Opsman VM via SSH, executes UAAC commands, and provides feedback on progress and errors.

.NOTES
    - Requires PowerShell 7+ and OpenSSH client.
    - Assumes operation mode is 'both'.
    - Prompts for sensitive information if not provided.
#>

param(
    [string]$OpsmanHost = "opsman.elasticsky.cloud",
    [string]$OpsmanUsername = "admin",
    [string]$OpsmanPassword = "VMware123!",
    [string]$OpsmanSshKey = "C:\Users\Administrator\.ssh\id_rsa_tanzu",
    [string]$ClientName = "hub-tas-collector",
    [string]$ClientSecret = "hub-tas-collector"
)

function Write-Info($msg)   { Write-Host "[INFO] $msg" -ForegroundColor Green }
function Write-Warn($msg)   { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-ErrorMsg($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }

function Prompt-IfEmpty([string]$var, [string]$prompt, [switch]$Secret) {
    if ([string]::IsNullOrWhiteSpace($var)) {
        if ($Secret) {
            return Read-Host -Prompt $prompt -AsSecureString | ConvertFrom-SecureString
        } else {
            return Read-Host -Prompt $prompt
        }
    }
    return $var
}

function SSH-Exec($Host, $Key, $Command) {
    $sshCmd = "ssh -i `"$Key`" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@$Host '$Command'"
    Write-Info "Executing on $Host: $Command"
    $output = & bash -c $sshCmd 2>&1
    return $output
}

# --- Main Script ---

# Prompt for required values if not provided
if (-not $OpsmanHost)     { $OpsmanHost     = Read-Host "Enter Opsman hostname (e.g. opsman.elasticsky.cloud)" }
if (-not $OpsmanUsername) { $OpsmanUsername = Read-Host "Enter Opsman username" }
if (-not $OpsmanPassword) { $OpsmanPassword = Read-Host "Enter Opsman password" -AsSecureString | ConvertFrom-SecureString }
if (-not $OpsmanSshKey)   { $OpsmanSshKey   = Read-Host "Enter path to Opsman SSH private key" }
if (-not (Test-Path $OpsmanSshKey)) { Write-ErrorMsg "SSH key file not found: $OpsmanSshKey"; exit 1 }
if (-not $ClientSecret)   { $ClientSecret   = Read-Host "Enter client secret for '$ClientName'" }

$OpsmanUrl = "https://$OpsmanHost"

# --- Get BOSH credentials and director IP from Opsman API ---
Write-Info "Retrieving BOSH credentials and director IP from Opsman API..."

# Get Opsman authentication token
$tokenCmd = @"
curl -s -k -X POST 'https://localhost/uaa/oauth/token' `
    -H 'Accept: application/json' `
    -H 'Content-Type: application/x-www-form-urlencoded' `
    -u 'opsman:' `
    -d 'grant_type=password&username=$OpsmanUsername&password=$OpsmanPassword'
"@
$tokenJson = SSH-Exec $OpsmanHost $OpsmanSshKey $tokenCmd
$OpsmanToken = ($tokenJson | ConvertFrom-Json).access_token
if (-not $OpsmanToken) { Write-ErrorMsg "Failed to obtain Opsman authentication token"; exit 1 }

# Get BOSH credentials
$credsCmd = @"
curl -s -k -X GET 'https://localhost/api/v0/deployed/director/credentials/bosh_commandline_credentials' `
    -H 'Authorization: Bearer $OpsmanToken' `
    -H 'Accept: application/json'
"@
$credsJson = SSH-Exec $OpsmanHost $OpsmanSshKey $credsCmd
$credentialString = ($credsJson | ConvertFrom-Json).credential
if (-not $credentialString) { Write-ErrorMsg "Failed to retrieve BOSH credentials"; exit 1 }

$uaaClientId    = ($credentialString -split " ") | Where-Object { $_ -like "BOSH_CLIENT=*" } | ForEach-Object { $_.Split("=")[1] }
$uaaClientSecret= ($credentialString -split " ") | Where-Object { $_ -like "BOSH_CLIENT_SECRET=*" } | ForEach-Object { $_.Split("=")[1] }
$boshDirectorIp = ($credentialString -split " ") | Where-Object { $_ -like "BOSH_ENVIRONMENT=*" } | ForEach-Object { $_.Split("=")[1] }

if (-not $uaaClientId -or -not $uaaClientSecret -or -not $boshDirectorIp) {
    Write-ErrorMsg "Could not parse BOSH credentials."
    exit 1
}

# --- Setup UAA client in BOSH Director ---
Write-Info "Setting up UAA client in BOSH Director..."
SSH-Exec $OpsmanHost $OpsmanSshKey "uaac target https://$boshDirectorIp:8443 --skip-ssl-validation"
SSH-Exec $OpsmanHost $OpsmanSshKey "uaac token client get '$uaaClientId' -s '$uaaClientSecret'"

$clientExists = SSH-Exec $OpsmanHost $OpsmanSshKey "uaac clients | grep '^$ClientName '"
if ($clientExists) {
    Write-Info "Client '$ClientName' already exists in BOSH Director. Updating secret..."
    SSH-Exec $OpsmanHost $OpsmanSshKey "uaac client update $ClientName --secret '$ClientSecret'"
    Write-Info "BOSH UAA client '$ClientName' secret updated successfully"
} else {
    Write-Info "Adding UAA client to BOSH Director: $ClientName"
    SSH-Exec $OpsmanHost $OpsmanSshKey "uaac client add $ClientName --secret '$ClientSecret' --authorized_grant_types client_credentials,refresh_token --authorities bosh.read --scope bosh.read"
    Write-Info "BOSH UAA client '$ClientName' added successfully"
}

# --- Setup UAA client in Opsman ---
Write-Info "Setting up UAA client in Opsman..."
$uaaTarget = "https://$OpsmanHost/uaa"
SSH-Exec $OpsmanHost $OpsmanSshKey "uaac target $uaaTarget --skip-ssl-validation"
SSH-Exec $OpsmanHost $OpsmanSshKey "echo -e '\n$OpsmanUsername\n$OpsmanPassword' | uaac token owner get opsman"

$clientExists = SSH-Exec $OpsmanHost $OpsmanSshKey "uaac clients | grep '^$ClientName '"
if ($clientExists) {
    Write-Info "Client '$ClientName' already exists in Opsman. Updating secret..."
    SSH-Exec $OpsmanHost $OpsmanSshKey "uaac client update $ClientName --secret '$ClientSecret'"
    Write-Info "Opsman UAA client '$ClientName' secret updated successfully"
} else {
    Write-Info "Adding UAA client to Opsman: $ClientName"
    SSH-Exec $OpsmanHost $OpsmanSshKey "uaac client add $ClientName --secret '$ClientSecret' --authorized_grant_types client_credentials,refresh_token --authorities scim.read"
    Write-Info "Opsman UAA client '$ClientName' added successfully"
}

# --- Verification ---
Write-Info "Verifying BOSH UAA client creation..."
SSH-Exec $OpsmanHost $OpsmanSshKey "uaac target https://$boshDirectorIp:8443 --skip-ssl-validation && uaac clients | grep -A 5 -B 5 '$ClientName' || echo '[WARN] Client not found in BOSH UAA listing'"

Write-Info "Verifying Opsman UAA client creation..."
SSH-Exec $OpsmanHost $OpsmanSshKey "uaac target $uaaTarget --skip-ssl-validation && uaac clients | grep -A 5 -B 5 '$ClientName' || echo '[WARN] Client not found in Opsman UAA listing'"

# --- Summary ---
Write-Host "`nFinal Configuration Summary:" -ForegroundColor Cyan
Write-Host "  Opsman URL: $OpsmanUrl"
Write-Host "  Client Name: $ClientName"
Write-Host "  Client Secret: [HIDDEN]"
Write-Host "  BOSH Director IP: $boshDirectorIp"
Write-Host "  BOSH Authorities: bosh.read"
Write-Host "  BOSH Scopes: bosh.read"
Write-Host "  Opsman Authorities: scim.read"
Write-Host "