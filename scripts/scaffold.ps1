#Requires -Version 5.1
<#
.SYNOPSIS
    Scaffold complete Apigee project from defaults.yaml
.EXAMPLE
    .\scaffold.ps1
    .\scaffold.ps1 -ConfigPath .\config\defaults.yaml -ProjectRoot C:\apigee-cicd
#>
param(
    [string]$ConfigPath  = (Join-Path $PSScriptRoot "..\config\defaults.yaml"),
    [string]$ProjectRoot = (Join-Path $PSScriptRoot "..")
)

. "$PSScriptRoot\config.ps1"

$cfg = Read-Yaml -Path $ConfigPath
$org = $cfg.org ?? $script:Defaults.Org
$env = $cfg.env ?? $script:Defaults.Env
$sfMap = $cfg.default_shared_flows ?? @{ security = "sf-security"; cors = "sf-cors"; logging = "sf-logging" }

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Apigee Scaffolder — org=$org  env=$env" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ═════════════════════════════════════════════════════════════════════
#  1. SHARED FLOWS
# ═════════════════════════════════════════════════════════════════════
Write-Host "── Shared Flows ──" -ForegroundColor Yellow

foreach ($sf in $cfg.shared_flows) {
    $name = $sf.name
    $desc = $sf.description ?? $name
    $root = Join-Path $ProjectRoot "sharedflows" $name "sharedflowbundle"

    $policyNames = @()
    $policyFiles = @{}

    foreach ($pol in $sf.policies) {
        switch ($pol.type) {
            "oauth-verify" {
                $policyNames += "OA-VerifyAccessToken"
                $policyFiles["OA-VerifyAccessToken.xml"] = New-OAuthVerifyPolicyXml
            }
            "json-threat" {
                $policyNames += "JT-JSONProtection"
                $policyFiles["JT-JSONProtection.xml"] = New-JSONThreatProtectionPolicyXml
            }
            "regex-threat" {
                $policyNames += "JS-ThreatProtection"
                $policyFiles["JS-ThreatProtection.xml"] = New-JSThreatProtectionPolicyXml
            }
            "cors-preflight" {
                $policyNames += "RF-CORSPreflight"
                $policyFiles["RF-CORSPreflight.xml"] = New-CORSPreflightPolicyXml
            }
            "cors-headers" {
                $policyNames += "AM-CORSHeaders"
                $policyFiles["AM-CORSHeaders.xml"] = New-CORSHeadersPolicyXml
            }
            "message-logging" {
                $policyNames += "ML-CloudLogging"
                $policyFiles["ML-CloudLogging.xml"] = New-MessageLoggingPolicyXml
            }
        }
    }

    Write-Host "  SharedFlow: $name ($($policyNames.Count) policies)" -ForegroundColor White
    Out-File-Safe (Join-Path $root "$name.xml") (New-SharedFlowBundleXml -Name $name -Description $desc -PolicyNames $policyNames)
    Out-File-Safe (Join-Path $root "sharedflows" "default.xml") (New-SharedFlowDefaultXml -PolicyNames $policyNames)

    foreach ($pf in $policyFiles.GetEnumerator()) {
        Out-File-Safe (Join-Path $root "policies" $pf.Key) $pf.Value
    }

    # JS resource for threat protection shared flow
    if ($policyFiles.ContainsKey("JS-ThreatProtection.xml")) {
        Out-File-Safe (Join-Path $root "resources" "jsc" "threat-protection.js") (New-ThreatProtectionJS)
    }

    Out-File-Safe (Join-Path $ProjectRoot "sharedflows" $name "pom.xml") (New-ChildPomXml -ArtifactId $name)
}

# ═════════════════════════════════════════════════════════════════════
#  2. API PROXIES
# ═════════════════════════════════════════════════════════════════════
Write-Host "`n── API Proxies ──" -ForegroundColor Yellow

foreach ($proxy in $cfg.api_proxies) {
    $name     = $proxy.name
    $basePath = $proxy.base_path ?? "/$name"
    $target   = $proxy.target_url ?? "https://httpbin.org/anything"
    $vhost    = $proxy.virtual_host ?? "default"
    $desc     = $proxy.description ?? $name
    $pol      = $proxy.policies ?? @{}
    $faults   = $proxy.fault_rules ?? @()
    $root     = Join-Path $ProjectRoot "apiproxies" $name "apiproxy"

    # Collect all policy names for bundle descriptor
    $allPolicies = @()
    $policyFiles = @{}

    # Spike Arrest
    if ($pol.spike_arrest) {
        $allPolicies += "SA-SpikeArrest"
        $policyFiles["SA-SpikeArrest.xml"] = New-SpikeArrestPolicyXml -Rate $pol.spike_arrest.rate
    }

    # OAuth or API Key verification
    if ($pol.oauth) {
        $allPolicies += "OA-VerifyAccessToken"
        $policyFiles["OA-VerifyAccessToken.xml"] = New-OAuthVerifyPolicyXml
    } else {
        $allPolicies += "VA-VerifyKey"
        $policyFiles["VA-VerifyKey.xml"] = New-VerifyApiKeyPolicyXml
    }

    # Quota
    if ($pol.quota) {
        $allPolicies += "QU-RateLimit"
        $policyFiles["QU-RateLimit.xml"] = New-QuotaPolicyXml `
            -AllowCount $pol.quota.allow_count `
            -Interval $pol.quota.interval `
            -TimeUnit $pol.quota.time_unit
    }

    # Security shared flow callout
    if ($pol.security_flow) {
        $allPolicies += "FC-Security"
        $policyFiles["FC-Security.xml"] = New-FlowCalloutPolicyXml -Name "FC-Security" -SharedFlowBundle ($sfMap.security ?? "sf-security")
    }

    # Threat protection (inline JS)
    if ($pol.threat_protection) {
        $allPolicies += "JS-ThreatProtection"
        $policyFiles["JS-ThreatProtection.xml"] = New-JSThreatProtectionPolicyXml
    }

    # Remove auth header before forwarding to backend
    if ($pol.remove_auth_header) {
        $allPolicies += "AM-RemoveAuthHeader"
        $policyFiles["AM-RemoveAuthHeader.xml"] = New-RemoveAuthHeaderPolicyXml
    }

    # CORS shared flow callout
    if ($pol.cors) {
        $allPolicies += "FC-CORS"
        $policyFiles["FC-CORS.xml"] = New-FlowCalloutPolicyXml -Name "FC-CORS" -SharedFlowBundle ($sfMap.cors ?? "sf-cors")
    }

    # Fault rules (RaiseFault policies)
    foreach ($fr in $faults) {
        $rfName = "RF-$($fr.name)"
        $allPolicies += $rfName
        $policyFiles["$rfName.xml"] = New-RaiseFaultPolicyXml `
            -Name $rfName `
            -StatusCode $fr.status_code `
            -ReasonPhrase $fr.reason `
            -Message $fr.message
    }

    Write-Host "  Proxy: $name ($($allPolicies.Count) policies)" -ForegroundColor White

    # Bundle descriptor
    Out-File-Safe (Join-Path $root "$name.xml") (New-ProxyBundleXml -Name $name -BasePath $basePath -Description $desc -PolicyNames $allPolicies)

    # ProxyEndpoint with policy steps + fault rules
    Out-File-Safe (Join-Path $root "proxies" "default.xml") (New-ProxyEndpointXml -Name $name -BasePath $basePath -VHost $vhost -Policies $pol -FaultRules $faults)

    # TargetEndpoint
    Out-File-Safe (Join-Path $root "targets" "default.xml") (New-TargetEndpointXml -Name $name -TargetUrl $target)

    # Policy files
    foreach ($pf in $policyFiles.GetEnumerator()) {
        Out-File-Safe (Join-Path $root "policies" $pf.Key) $pf.Value
    }

    # JS resources
    if ($pol.threat_protection) {
        Out-File-Safe (Join-Path $root "resources" "jsc" "threat-protection.js") (New-ThreatProtectionJS)
    }
    New-Item -ItemType Directory -Path (Join-Path $root "resources" "jsc") -Force | Out-Null

    # Child pom
    Out-File-Safe (Join-Path $ProjectRoot "apiproxies" $name "pom.xml") (New-ChildPomXml -ArtifactId $name)
}

# ═════════════════════════════════════════════════════════════════════
#  3. edge.json (Products + Developers + Apps)
# ═════════════════════════════════════════════════════════════════════
Write-Host "`n── Configuration ──" -ForegroundColor Yellow
Out-File-Safe (Join-Path $ProjectRoot "edge.json") (New-EdgeJson -Config $cfg)

# ═════════════════════════════════════════════════════════════════════
#  4. Root pom.xml + lint config + .gitignore
# ═════════════════════════════════════════════════════════════════════
Out-File-Safe (Join-Path $ProjectRoot "pom.xml") (New-RootPomXml -Org $org -Env $env)

Out-File-Safe (Join-Path $ProjectRoot ".apigeelintrc") (@{ excluded = @{}; maxWarnings = -1; profile = "apigeex" } | ConvertTo-Json)

Out-File-Safe (Join-Path $ProjectRoot ".gitignore") @"
target/
*.class
.idea/
*.iml
node_modules/
.DS_Store
"@

# ═════════════════════════════════════════════════════════════════════
#  Summary
# ═════════════════════════════════════════════════════════════════════
$proxyCount = ($cfg.api_proxies | Measure-Object).Count
$sfCount    = ($cfg.shared_flows | Measure-Object).Count
$prodCount  = ($cfg.api_products | Measure-Object).Count
$appCount   = ($cfg.apps | Measure-Object).Count

Write-Host "`n========================================" -ForegroundColor Green
Write-Host " Scaffold Complete!" -ForegroundColor Green
Write-Host "   Proxies:       $proxyCount" -ForegroundColor White
Write-Host "   Shared Flows:  $sfCount" -ForegroundColor White
Write-Host "   API Products:  $prodCount" -ForegroundColor White
Write-Host "   Apps:          $appCount" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor Green
