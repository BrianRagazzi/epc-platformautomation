# PowerShell script to set up and deploy pipelines in Concourse
# This script performs the following actions:
# 1. Check that Concourse server is responding
# 2. Check that Fly CLI tool is installed, install if not
# 3. Login to Concourse with Fly
# 4. For each pipeline-*.yml in ./pipelines (excluding testing), deploy to Concourse

### Variables
$pipelineRepo   = "https://github.com/BrianRagazzi/epc-platformautomation.git"
$concourseURL   = "http://concourse.elasticsky.cloud:8080"
$concourseUser  = "admin"
$concoursePass  = "VMware123!"
$paramsSource   = "https://fileshare.tnz-field-epc.lvn.broadcom.net/config/params.yml"
$paramsFile     = "params.yml"
$concoursePath  = 'C:\concourse\'
$flyDownloadURL = "$concourseURL/api/v1/cli?arch=amd64&platform=windows"
$pipelinesPath  = ".\pipelines"
$paramsPath     = ".\params"

### Global Variables for Script State
$script:ErrorCount = 0
$script:SuccessCount = 0

#region Logging Functions

function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        "INFO"    { Write-Host $logMessage -ForegroundColor White }
        "WARN"    { Write-Host $logMessage -ForegroundColor Yellow }
        "ERROR"   { Write-Host $logMessage -ForegroundColor Red }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
    }
}

#endregion

#region Core Functions

function Test-ConcourseConnectivity {
    <#
    .SYNOPSIS
    Tests connectivity to the Concourse server
    
    .DESCRIPTION
    Attempts to connect to the Concourse server URL to verify it's accessible
    
    .OUTPUTS
    Boolean - True if connection successful, False otherwise
    #>
    
    Write-Log "Testing connectivity to Concourse server: $concourseURL" -Level "INFO"
    
    try {
        $response = Invoke-WebRequest -Uri $concourseURL -Method Head -TimeoutSec 10 -UseBasicParsing
        if ($response.StatusCode -eq 200) {
            Write-Log "Successfully connected to Concourse server" -Level "SUCCESS"
            return $true
        } else {
            Write-Log "Concourse server responded with status code: $($response.StatusCode)" -Level "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "Failed to connect to Concourse server: $($_.Exception.Message)" -Level "ERROR"
        Write-Log "Please verify that the Concourse server is running and accessible at: $concourseURL" -Level "ERROR"
        return $false
    }
}

function Install-FlyCLI {
    <#
    .SYNOPSIS
    Checks for Fly CLI installation and installs if not found
    
    .DESCRIPTION
    Verifies if Fly CLI is available in PATH, and if not, downloads and installs it
    
    .OUTPUTS
    Boolean - True if Fly CLI is available after function execution, False otherwise
    #>
    
    Write-Log "Checking for Fly CLI installation..." -Level "INFO"
    
    # Check if fly.exe is already available in PATH
    try {
        $flyVersion = & fly --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Fly CLI is already installed: $flyVersion" -Level "SUCCESS"
            return $true
        }
    }
    catch {
        # Fly CLI not found in PATH, proceed with installation
    }
    
    Write-Log "Fly CLI not found. Installing Fly CLI..." -Level "INFO"
    
    try {
        # Create concourse directory
        Write-Log "Creating directory: $concoursePath" -Level "INFO"
        if (!(Test-Path $concoursePath)) {
            New-Item -ItemType Directory -Path $concoursePath -Force | Out-Null
        }
        
        # Update PATH environment variable
        Write-Log "Adding $concoursePath to PATH environment variable" -Level "INFO"
        [Environment]::SetEnvironmentVariable('PATH', "$ENV:PATH;$concoursePath", 'USER')
        
        # Update current session PATH
        $env:PATH += ";$concoursePath"
        
        # Download Fly CLI
        Write-Log "Downloading Fly CLI from: $flyDownloadURL" -Level "INFO"
        $flyExePath = Join-Path $concoursePath "fly.exe"
        Invoke-WebRequest $flyDownloadURL -OutFile $flyExePath
        
        # Verify download
        if (Test-Path $flyExePath) {
            Write-Log "Fly CLI successfully downloaded to: $flyExePath" -Level "SUCCESS"
            
            # Test the installation
            try {
                $flyVersion = & $flyExePath --version 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Fly CLI installation verified: $flyVersion" -Level "SUCCESS"
                    return $true
                } else {
                    Write-Log "Fly CLI downloaded but failed to execute properly" -Level "ERROR"
                    return $false
                }
            }
            catch {
                Write-Log "Fly CLI downloaded but failed to execute: $($_.Exception.Message)" -Level "ERROR"
                return $false
            }
        } else {
            Write-Log "Failed to download Fly CLI to: $flyExePath" -Level "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "Error during Fly CLI installation: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Get-ParametersFile {
    <#
    .SYNOPSIS
    Downloads the remote parameters file and saves it locally
    
    .DESCRIPTION
    Retrieves the remote file specified in $paramsSource and saves it to $paramsPath\$paramsFile,
    overwriting any existing files
    
    .OUTPUTS
    Boolean - True if download successful, False otherwise
    #>
    
    Write-Log "Downloading parameters file from remote source..." -Level "INFO"
    Write-Log "Source: $paramsSource" -Level "INFO"
    
    try {
        # Ensure the params directory exists
        if (!(Test-Path $paramsPath)) {
            Write-Log "Creating parameters directory: $paramsPath" -Level "INFO"
            New-Item -ItemType Directory -Path $paramsPath -Force | Out-Null
        }
        
        $paramsFilePath = Join-Path $paramsPath $paramsFile
        Write-Log "Target: $paramsFilePath" -Level "INFO"
        
        # Download the parameters file
        Write-Log "Downloading parameters file..." -Level "INFO"
        Invoke-WebRequest -Uri $paramsSource -OutFile $paramsFilePath -UseBasicParsing
        
        # Verify the download
        if (Test-Path $paramsFilePath) {
            $fileSize = (Get-Item $paramsFilePath).Length
            Write-Log "Successfully downloaded parameters file ($fileSize bytes)" -Level "SUCCESS"
            return $true
        } else {
            Write-Log "Parameters file was not created at expected location: $paramsFilePath" -Level "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "Failed to download parameters file: $($_.Exception.Message)" -Level "ERROR"
        Write-Log "Please verify that the source URL is accessible: $paramsSource" -Level "ERROR"
        return $false
    }
}

function Connect-ToConcourse {
    <#
    .SYNOPSIS
    Authenticates with the Concourse server using Fly CLI
    
    .DESCRIPTION
    Logs into Concourse using the provided credentials
    
    .OUTPUTS
    Boolean - True if login successful, False otherwise
    #>
    
    Write-Log "Logging into Concourse server..." -Level "INFO"
    Write-Log "Target: $concourseURL" -Level "INFO"
    Write-Log "User: $concourseUser" -Level "INFO"
    
    try {
        # Execute fly login command
        $loginArgs = @(
            "-t", "ci",
            "login",
            "-k",
            "-c", $concourseURL,
            "-u", $concourseUser,
            "-p", $concoursePass
        )
        
        Write-Log "Executing: fly $($loginArgs -join ' ')" -Level "INFO"
        
        # Capture both stdout and stderr
        $process = Start-Process -FilePath "fly" -ArgumentList $loginArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput "login_output.tmp" -RedirectStandardError "login_error.tmp"
        
        $output = ""
        $errorOutput = ""
        
        if (Test-Path "login_output.tmp") {
            $output = Get-Content "login_output.tmp" -Raw
            Remove-Item "login_output.tmp" -Force
        }
        
        if (Test-Path "login_error.tmp") {
            $errorOutput = Get-Content "login_error.tmp" -Raw
            Remove-Item "login_error.tmp" -Force
        }
        
        if ($process.ExitCode -eq 0) {
            Write-Log "Successfully logged into Concourse" -Level "SUCCESS"
            return $true
        } else {
            Write-Log "Failed to login to Concourse (Exit Code: $($process.ExitCode))" -Level "ERROR"
            if ($errorOutput) {
                Write-Log "Error details: $errorOutput" -Level "ERROR"
            }
            if ($output) {
                Write-Log "Output: $output" -Level "ERROR"
            }
            return $false
        }
    }
    catch {
        Write-Log "Exception during Concourse login: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

function Deploy-Pipelines {
    <#
    .SYNOPSIS
    Processes and deploys pipeline files to Concourse
    
    .DESCRIPTION
    Finds all pipeline-*.yml files in the pipelines directory (excluding testing subdirectory)
    and deploys them to Concourse using Fly CLI
    
    .OUTPUTS
    Boolean - True if at least one pipeline was deployed successfully, False if all failed
    #>
    
    Write-Log "Starting pipeline deployment process..." -Level "INFO"
    
    # Verify paths exist
    if (!(Test-Path $pipelinesPath)) {
        Write-Log "Pipelines directory not found: $pipelinesPath" -Level "ERROR"
        return $false
    }
    
    $paramsFilePath = Join-Path $paramsPath $paramsFile
    if (!(Test-Path $paramsFilePath)) {
        Write-Log "Parameters file not found: $paramsFilePath" -Level "ERROR"
        return $false
    }
    
    Write-Log "Using parameters file: $paramsFilePath" -Level "INFO"
    
    # Find all pipeline files, excluding the testing directory
    $pipelineFiles = Get-ChildItem -Path $pipelinesPath -Filter "pipeline-*.yml" -File | Where-Object {
        $_.DirectoryName -notlike "*testing*"
    }
    
    if ($pipelineFiles.Count -eq 0) {
        Write-Log "No pipeline files found matching pattern 'pipeline-*.yml' in $pipelinesPath" -Level "WARN"
        return $false
    }
    
    Write-Log "Found $($pipelineFiles.Count) pipeline file(s) to deploy" -Level "INFO"
    
    $deploymentResults = @()
    
    foreach ($pipelineFile in $pipelineFiles) {
        Write-Log "Processing pipeline file: $($pipelineFile.Name)" -Level "INFO"
        
        # Extract pipeline name from filename
        # Example: pipeline-foundation-core.yml -> foundation-core
        $pipelineName = $pipelineFile.BaseName -replace "^pipeline-", ""
        
        Write-Log "Extracted pipeline name: $pipelineName" -Level "INFO"
        
        try {
            # Build fly command arguments
            $deployArgs = @(
                "-t", "ci",
                "sp",
                "-p", $pipelineName,
                "-c", $pipelineFile.FullName,
                "-l", $paramsFilePath,
                "--check-creds",
                "-n"
            )
            
            Write-Log "Deploying pipeline '$pipelineName'..." -Level "INFO"
            Write-Log "Command: fly $($deployArgs -join ' ')" -Level "INFO"
            
            # Execute deployment
            $process = Start-Process -FilePath "fly" -ArgumentList $deployArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput "deploy_output.tmp" -RedirectStandardError "deploy_error.tmp"
            
            $output = ""
            $errorOutput = ""
            
            if (Test-Path "deploy_output.tmp") {
                $output = Get-Content "deploy_output.tmp" -Raw
                Remove-Item "deploy_output.tmp" -Force
            }
            
            if (Test-Path "deploy_error.tmp") {
                $errorOutput = Get-Content "deploy_error.tmp" -Raw
                Remove-Item "deploy_error.tmp" -Force
            }
            
            if ($process.ExitCode -eq 0) {
                Write-Log "Successfully deployed pipeline '$pipelineName'" -Level "SUCCESS"
                $script:SuccessCount++
                $deploymentResults += [PSCustomObject]@{
                    Pipeline = $pipelineName
                    Status = "Success"
                    Message = "Deployed successfully"
                }
            } else {
                Write-Log "Failed to deploy pipeline '$pipelineName' (Exit Code: $($process.ExitCode))" -Level "ERROR"
                $script:ErrorCount++
                $deploymentResults += [PSCustomObject]@{
                    Pipeline = $pipelineName
                    Status = "Failed"
                    Message = "Exit Code: $($process.ExitCode)"
                }
                
                if ($errorOutput) {
                    Write-Log "Error details: $errorOutput" -Level "ERROR"
                }
                if ($output) {
                    Write-Log "Output: $output" -Level "ERROR"
                }
            }
        }
        catch {
            Write-Log "Exception while deploying pipeline '$pipelineName': $($_.Exception.Message)" -Level "ERROR"
            $script:ErrorCount++
            $deploymentResults += [PSCustomObject]@{
                Pipeline = $pipelineName
                Status = "Failed"
                Message = $_.Exception.Message
            }
        }
        
        Write-Log "Completed processing pipeline: $pipelineName" -Level "INFO"
        Write-Log "----------------------------------------" -Level "INFO"
    }
    
    # Display deployment summary
    Write-Log "DEPLOYMENT SUMMARY" -Level "INFO"
    Write-Log "==================" -Level "INFO"
    Write-Log "Total pipelines processed: $($deploymentResults.Count)" -Level "INFO"
    Write-Log "Successful deployments: $script:SuccessCount" -Level "SUCCESS"
    Write-Log "Failed deployments: $script:ErrorCount" -Level $(if ($script:ErrorCount -gt 0) { "ERROR" } else { "INFO" })
    
    foreach ($result in $deploymentResults) {
        $level = if ($result.Status -eq "Success") { "SUCCESS" } else { "ERROR" }
        Write-Log "  $($result.Pipeline): $($result.Status) - $($result.Message)" -Level $level
    }
    
    return ($script:SuccessCount -gt 0)
}

#endregion

#region Main Execution

function Main {
    <#
    .SYNOPSIS
    Main execution function that orchestrates the entire pipeline deployment process
    
    .DESCRIPTION
    Executes all the required steps in sequence with proper error handling
    #>
    
    Write-Log "========================================" -Level "INFO"
    Write-Log "Starting Concourse Pipeline Deployment" -Level "INFO"
    Write-Log "========================================" -Level "INFO"
    
    try {
        # Step 1: Test Concourse connectivity
        Write-Log "Step 1: Testing Concourse server connectivity" -Level "INFO"
        if (!(Test-ConcourseConnectivity)) {
            Write-Log "Cannot proceed without Concourse server connectivity. Exiting." -Level "ERROR"
            exit 1
        }
        
        # Step 2: Check/Install Fly CLI
        Write-Log "Step 2: Verifying Fly CLI installation" -Level "INFO"
        if (!(Install-FlyCLI)) {
            Write-Log "Cannot proceed without Fly CLI. Exiting." -Level "ERROR"
            exit 1
        }
        
        # Step 3: Download parameters file
        Write-Log "Step 3: Downloading parameters file" -Level "INFO"
        if (!(Get-ParametersFile)) {
            Write-Log "Cannot proceed without parameters file. Exiting." -Level "ERROR"
            exit 1
        }
        
        # Step 4: Login to Concourse
        Write-Log "Step 4: Authenticating with Concourse" -Level "INFO"
        if (!(Connect-ToConcourse)) {
            Write-Log "Cannot proceed without Concourse authentication. Exiting." -Level "ERROR"
            exit 1
        }
        
        # Step 5: Deploy pipelines
        Write-Log "Step 5: Deploying pipelines" -Level "INFO"
        $deploymentSuccess = Deploy-Pipelines
        
        # Final summary
        Write-Log "========================================" -Level "INFO"
        if ($deploymentSuccess) {
            Write-Log "Pipeline deployment process completed with $script:SuccessCount successful deployment(s)" -Level "SUCCESS"
            if ($script:ErrorCount -gt 0) {
                Write-Log "Note: $script:ErrorCount pipeline(s) failed to deploy" -Level "WARN"
                exit 2  # Partial success
            } else {
                Write-Log "All pipelines deployed successfully!" -Level "SUCCESS"
                exit 0  # Complete success
            }
        } else {
            Write-Log "Pipeline deployment process failed - no pipelines were deployed successfully" -Level "ERROR"
            exit 1  # Complete failure
        }
    }
    catch {
        Write-Log "Unexpected error in main execution: $($_.Exception.Message)" -Level "ERROR"
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
        exit 1
    }
}

#endregion

# Execute main function
Main