#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy Apigee artifacts via Maven.
.EXAMPLE
    .\deploy.ps1 -Target all -UseGcloud
    .\deploy.ps1 -Target proxy -Name petstore-api -Env dev -UseGcloud
    .\deploy.ps1 -Target sharedflow -Name sf-security -UseGcloud
    .\deploy.ps1 -Target config -UseGcloud
#>
param(
    [Parameter(Mandatory)]
    [ValidateSet("all", "proxy", "sharedflow", "config")]
    [string]$Target,

    [string]$Name,
    [string]$Env         = $env:APIGEE_ENV ?? "eval",
    [string]$Org         = $env:APIGEE_ORG ?? "my-gcp-project",
    [string]$ProjectRoot = (Join-Path $PSScriptRoot ".."),
    [switch]$UseGcloud,
    [switch]$DryRun
)

. "$PSScriptRoot\config.ps1"

$token = Get-ApigeeToken -UseGcloud:$UseGcloud
Write-Host "`nDeploying to org=$Org  env=$Env`n" -ForegroundColor Cyan

function Invoke-Maven {
    param([string]$WorkDir, [string]$ApiType, [string]$ExtraArgs = "")
    $pomPath = Join-Path $ProjectRoot "pom.xml"
    $cmd = @(
        "mvn", "clean", "install",
        "-P$Env",
        "-Dapigee.org=$Org",
        "-Dapigee.env=$Env",
        "-Dapigee.bearer=$token",
        "-Dapigee.apitype=$ApiType",
        "-Dapigee.options=override",
        "-f", "`"$pomPath`""
    )
    if ($ExtraArgs) { $cmd += $ExtraArgs }
    $cmdStr = $cmd -join " "

    if ($DryRun) {
        Write-Host "  [DRY RUN] $cmdStr" -ForegroundColor DarkYellow
        return
    }

    Write-Host "  > $cmdStr" -ForegroundColor DarkGray
    Push-Location $WorkDir
    try { Invoke-Expression $cmdStr }
    finally { Pop-Location }
    if ($LASTEXITCODE -ne 0) { throw "Deploy failed: $WorkDir" }
    Write-Host "  OK" -ForegroundColor Green
}

function Deploy-SharedFlows([string]$Single) {
    $sfRoot = Join-Path $ProjectRoot "sharedflows"
    $dirs = if ($Single) { @(Get-Item (Join-Path $sfRoot $Single)) }
            else { @(Get-ChildItem $sfRoot -Directory) }
    foreach ($d in $dirs) {
        Write-Host "`n  SharedFlow: $($d.Name)" -ForegroundColor Yellow
        Invoke-Maven -WorkDir $d.FullName -ApiType "sharedflow"
    }
}

function Deploy-Proxies([string]$Single) {
    $pxRoot = Join-Path $ProjectRoot "apiproxies"
    $dirs = if ($Single) { @(Get-Item (Join-Path $pxRoot $Single)) }
            else { @(Get-ChildItem $pxRoot -Directory) }
    foreach ($d in $dirs) {
        Write-Host "`n  Proxy: $($d.Name)" -ForegroundColor Yellow
        Invoke-Maven -WorkDir $d.FullName -ApiType "configbundle"
    }
}

function Deploy-Config {
    Write-Host "`n  Config: products + developers + apps" -ForegroundColor Yellow
    $cmd = "mvn clean install -P$Env -Dapigee.org=$Org -Dapigee.env=$Env -Dapigee.bearer=$token -Dapigee.config.options=update -Dapigee.config.dir=`"$ProjectRoot`" -f `"$(Join-Path $ProjectRoot 'pom.xml')`""
    if ($DryRun) { Write-Host "  [DRY RUN] $cmd" -ForegroundColor DarkYellow; return }
    Invoke-Expression $cmd
    if ($LASTEXITCODE -ne 0) { throw "Config deploy failed" }
    Write-Host "  OK" -ForegroundColor Green
}

switch ($Target) {
    "sharedflow" { Deploy-SharedFlows -Single $Name }
    "proxy"      { Deploy-Proxies -Single $Name }
    "config"     { Deploy-Config }
    "all" {
        Write-Host "Step 1/3: Shared Flows" -ForegroundColor Cyan
        Deploy-SharedFlows
        Write-Host "`nStep 2/3: API Proxies" -ForegroundColor Cyan
        Deploy-Proxies
        Write-Host "`nStep 3/3: Configuration" -ForegroundColor Cyan
        Deploy-Config
    }
}

Write-Host "`nDeployment complete.`n" -ForegroundColor Green
