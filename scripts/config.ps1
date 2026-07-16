#Requires -Version 5.1
# ─────────────────────────────────────────────────────────────────────
# config.ps1 — Shared configuration, XML/JSON template builders
# Dot-source: . "$PSScriptRoot\config.ps1"
# ─────────────────────────────────────────────────────────────────────

$script:Defaults = @{
    Org             = $env:APIGEE_ORG ?? "my-gcp-project"
    Env             = $env:APIGEE_ENV ?? "eval"
    HostUrl         = "https://apigee.googleapis.com"
    MavenPluginVer  = "2.5.1"
    ConfigPluginVer = "2.7.1"
    LintProfile     = "apigeex"
}

# ── Helpers ──────────────────────────────────────────────────────────

function Read-Yaml {
    param([string]$Path)
    if (-not (Get-Module -ListAvailable powershell-yaml -EA SilentlyContinue)) {
        Install-Module powershell-yaml -Scope CurrentUser -Force -Confirm:$false
    }
    Import-Module powershell-yaml
    return Get-Content $Path -Raw | ConvertFrom-Yaml
}

function Out-File-Safe {
    param([string]$Path, [string]$Content)
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  + $Path" -ForegroundColor Green
}

# ═════════════════════════════════════════════════════════════════════
#  POLICY XML TEMPLATES
# ═════════════════════════════════════════════════════════════════════

# ── Quota ────────────────────────────────────────────────────────────
function New-QuotaPolicyXml {
    param(
        [string]$Name = "QU-RateLimit",
        [int]$AllowCount = 100,
        [int]$Interval = 1,
        [string]$TimeUnit = "minute"
    )
    return @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Quota name="$Name" type="calendar">
    <DisplayName>$Name</DisplayName>
    <Allow count="$AllowCount" countRef="verifyapikey.VA-VerifyKey.apiproduct.developer.quota.limit"/>
    <Interval ref="verifyapikey.VA-VerifyKey.apiproduct.developer.quota.interval">$Interval</Interval>
    <TimeUnit ref="verifyapikey.VA-VerifyKey.apiproduct.developer.quota.timeunit">$TimeUnit</TimeUnit>
    <Distributed>true</Distributed>
    <Synchronous>true</Synchronous>
    <StartTime>2024-01-01 00:00:00</StartTime>
    <Identifier ref="request.header.x-api-key"/>
</Quota>
"@
}

# ── Spike Arrest ─────────────────────────────────────────────────────
function New-SpikeArrestPolicyXml {
    param(
        [string]$Name = "SA-SpikeArrest",
        [string]$Rate = "30ps"       # 30ps = 30/sec, 10pm = 10/min
    )
    return @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<SpikeArrest name="$Name">
    <DisplayName>$Name</DisplayName>
    <Rate>$Rate</Rate>
    <Identifier ref="request.header.x-api-key"/>
    <UseEffectiveCount>true</UseEffectiveCount>
</SpikeArrest>
"@
}

# ── OAuth v2 — Verify Access Token ───────────────────────────────────
function New-OAuthVerifyPolicyXml {
    param([string]$Name = "OA-VerifyAccessToken")
    return @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<OAuthV2 name="$Name">
    <DisplayName>$Name</DisplayName>
    <Operation>VerifyAccessToken</Operation>
    <ExternalAuthorization>false</ExternalAuthorization>
    <SupportedGrantTypes/>
    <GenerateResponse enabled="true"/>
</OAuthV2>
"@
}

# ── Verify API Key ───────────────────────────────────────────────────
function New-VerifyApiKeyPolicyXml {
    param([string]$Name = "VA-VerifyKey")
    return @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<VerifyAPIKey name="$Name">
    <DisplayName>$Name</DisplayName>
    <APIKey ref="request.header.x-api-key"/>
</VerifyAPIKey>
"@
}

# ── Flow Callout ─────────────────────────────────────────────────────
function New-FlowCalloutPolicyXml {
    param(
        [string]$Name,
        [string]$SharedFlowBundle
    )
    return @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<FlowCallout name="$Name">
    <DisplayName>$Name</DisplayName>
    <SharedFlowBundle>$SharedFlowBundle</SharedFlowBundle>
</FlowCallout>
"@
}

# ── Assign Message — Remove Auth Header ──────────────────────────────
function New-RemoveAuthHeaderPolicyXml {
    param([string]$Name = "AM-RemoveAuthHeader")
    return @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<AssignMessage name="$Name">
    <DisplayName>$Name</DisplayName>
    <Remove>
        <Headers>
            <Header name="Authorization"/>
            <Header name="x-api-key"/>
        </Headers>
    </Remove>
    <AssignTo createNew="false" transport="http" type="request"/>
    <IgnoreUnresolvedVariables>true</IgnoreUnresolvedVariables>
</AssignMessage>
"@
}

# ── Raise Fault ──────────────────────────────────────────────────────
function New-RaiseFaultPolicyXml {
    param(
        [string]$Name,
        [int]$StatusCode,
        [string]$ReasonPhrase,
        [string]$Message
    )
    return @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<RaiseFault name="$Name">
    <DisplayName>$Name</DisplayName>
    <FaultResponse>
        <Set>
            <Headers>
                <Header name="Content-Type">application/json</Header>
            </Headers>
            <Payload contentType="application/json">
{
  "error": {
    "code": $StatusCode,
    "status": "$ReasonPhrase",
    "message": "$Message"
  }
}
            </Payload>
            <StatusCode>$StatusCode</StatusCode>
            <ReasonPhrase>$ReasonPhrase</ReasonPhrase>
        </Set>
    </FaultResponse>
    <IgnoreUnresolvedVariables>true</IgnoreUnresolvedVariables>
</RaiseFault>
"@
}

# ── JavaScript Threat Protection ─────────────────────────────────────
function New-JSThreatProtectionPolicyXml {
    param([string]$Name = "JS-ThreatProtection")
    return @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Javascript name="$Name" timeLimit="200">
    <DisplayName>$Name</DisplayName>
    <ResourceURL>jsc://threat-protection.js</ResourceURL>
</Javascript>
"@
}

function New-ThreatProtectionJS {
    return @"
// Basic threat protection: block SQL injection and XSS patterns
var payload = context.getVariable("request.content") || "";
var uri = context.getVariable("request.uri") || "";
var check = payload + uri;

var sqlPatterns = /(\b(SELECT|INSERT|UPDATE|DELETE|DROP|UNION|ALTER|CREATE|EXEC)\b)/gi;
var xssPatterns = /(<script|javascript:|on\w+\s*=)/gi;

if (sqlPatterns.test(check) || xssPatterns.test(check)) {
    throw new Error("ThreatDetected");
}
"@
}

# ── JSON Threat Protection ───────────────────────────────────────────
function New-JSONThreatProtectionPolicyXml {
    param([string]$Name = "JT-JSONProtection")
    return @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<JSONThreatProtection name="$Name">
    <DisplayName>$Name</DisplayName>
    <Source>request</Source>
    <ArrayElementCount>20</ArrayElementCount>
    <ContainerDepth>10</ContainerDepth>
    <ObjectEntryCount>25</ObjectEntryCount>
    <ObjectEntryNameLength>50</ObjectEntryNameLength>
    <StringValueLength>500</StringValueLength>
</JSONThreatProtection>
"@
}

# ── CORS — Assign Message (response headers) ────────────────────────
function New-CORSHeadersPolicyXml {
    param([string]$Name = "AM-CORSHeaders")
    return @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<AssignMessage name="$Name">
    <DisplayName>$Name</DisplayName>
    <AssignTo createNew="false" transport="http" type="response"/>
    <Set>
        <Headers>
            <Header name="Access-Control-Allow-Origin">*</Header>
            <Header name="Access-Control-Allow-Methods">GET, POST, PUT, DELETE, OPTIONS</Header>
            <Header name="Access-Control-Allow-Headers">Content-Type, Authorization, x-api-key</Header>
            <Header name="Access-Control-Max-Age">3600</Header>
        </Headers>
    </Set>
    <IgnoreUnresolvedVariables>true</IgnoreUnresolvedVariables>
</AssignMessage>
"@
}

# ── CORS — Preflight (RaiseFault to return 200 on OPTIONS) ──────────
function New-CORSPreflightPolicyXml {
    param([string]$Name = "RF-CORSPreflight")
    return @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<RaiseFault name="$Name">
    <DisplayName>$Name</DisplayName>
    <FaultResponse>
        <Set>
            <Headers>
                <Header name="Access-Control-Allow-Origin">*</Header>
                <Header name="Access-Control-Allow-Methods">GET, POST, PUT, DELETE, OPTIONS</Header>
                <Header name="Access-Control-Allow-Headers">Content-Type, Authorization, x-api-key</Header>
                <Header name="Access-Control-Max-Age">3600</Header>
            </Headers>
            <Payload contentType="application/json">{}</Payload>
            <StatusCode>200</StatusCode>
            <ReasonPhrase>OK</ReasonPhrase>
        </Set>
    </FaultResponse>
    <IgnoreUnresolvedVariables>true</IgnoreUnresolvedVariables>
</RaiseFault>
"@
}

# ── Message Logging (Stackdriver / Cloud Logging) ────────────────────
function New-MessageLoggingPolicyXml {
    param([string]$Name = "ML-CloudLogging")
    return @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<MessageLogging name="$Name">
    <DisplayName>$Name</DisplayName>
    <CloudLogging>
        <LogName>projects/{organization.name}/logs/apigee-api-logs</LogName>
        <Message contentType="application/json">{
  "logName": "{organization.name}",
  "proxy": "{apiproxy.name}",
  "verb": "{request.verb}",
  "uri": "{request.uri}",
  "status": "{response.status.code}",
  "clientIp": "{client.ip}",
  "latency": "{target.received.end.timestamp - target.sent.start.timestamp}",
  "timestamp": "{system.timestamp}"
}</Message>
        <Labels>
            <Label><Key>proxy</Key><Value>{apiproxy.name}</Value></Label>
            <Label><Key>env</Key><Value>{environment.name}</Value></Label>
        </Labels>
    </CloudLogging>
    <logLevel>INFO</logLevel>
</MessageLogging>
"@
}

# ═════════════════════════════════════════════════════════════════════
#  PROXY / SHARED FLOW BUNDLE XML
# ═════════════════════════════════════════════════════════════════════

function New-ProxyBundleXml {
    param([string]$Name, [string]$BasePath, [string]$Description, [string[]]$PolicyNames)
    $pNodes = ($PolicyNames | ForEach-Object { "        <Policy>$_</Policy>" }) -join "`n"
    return @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<APIProxy revision="1" name="$Name">
    <DisplayName>$Name</DisplayName>
    <Description>$Description</Description>
    <BasePaths>$BasePath</BasePaths>
    <Policies>
$pNodes
    </Policies>
    <ProxyEndpoints><ProxyEndpoint>default</ProxyEndpoint></ProxyEndpoints>
    <TargetEndpoints><TargetEndpoint>default</TargetEndpoint></TargetEndpoints>
    <Resources/>
</APIProxy>
"@
}

function New-ProxyEndpointXml {
    param(
        [string]$Name,
        [string]$BasePath,
        [string]$VHost,
        [hashtable]$Policies,
        [array]$FaultRules
    )

    # Build PreFlow request steps
    $preFlowSteps = @()
    if ($Policies.spike_arrest)       { $preFlowSteps += "                <Step><Name>SA-SpikeArrest</Name></Step>" }
    if ($Policies.oauth)              { $preFlowSteps += "                <Step><Name>OA-VerifyAccessToken</Name></Step>" }
    if (-not $Policies.oauth)         { $preFlowSteps += "                <Step><Name>VA-VerifyKey</Name></Step>" }
    if ($Policies.quota)              { $preFlowSteps += "                <Step><Name>QU-RateLimit</Name></Step>" }
    if ($Policies.security_flow)      { $preFlowSteps += "                <Step><Name>FC-Security</Name></Step>" }
    if ($Policies.threat_protection)  { $preFlowSteps += "                <Step><Name>JS-ThreatProtection</Name></Step>" }
    if ($Policies.remove_auth_header) { $preFlowSteps += "                <Step><Name>AM-RemoveAuthHeader</Name></Step>" }
    $preFlowBlock = $preFlowSteps -join "`n"

    # Build PostFlow response steps
    $postFlowSteps = @()
    if ($Policies.cors) { $postFlowSteps += "                <Step><Name>FC-CORS</Name></Step>" }
    $postFlowBlock = $postFlowSteps -join "`n"

    # Build CORS preflight conditional flow
    $corsFlow = ""
    if ($Policies.cors) {
        $corsFlow = @"

    <Flows>
        <Flow name="OptionsPreFlight">
            <Description>CORS preflight</Description>
            <Request/>
            <Response>
                <Step><Name>FC-CORS</Name></Step>
            </Response>
            <Condition>request.verb == "OPTIONS"</Condition>
        </Flow>
    </Flows>
"@
    } else {
        $corsFlow = "`n    <Flows/>"
    }

    # Build FaultRules
    $faultRulesBlock = ""
    if ($FaultRules -and $FaultRules.Count -gt 0) {
        $rules = $FaultRules | ForEach-Object {
            $rfName = "RF-$($_.name)"
            @"
        <FaultRule name="$($_.name)">
            <Condition>$($_.condition)</Condition>
            <Step><Name>$rfName</Name></Step>
        </FaultRule>
"@
        }
        $faultRulesBlock = @"

    <FaultRules>
$($rules -join "`n")
    </FaultRules>
    <DefaultFaultRule name="DefaultFault">
        <AlwaysEnforce>true</AlwaysEnforce>
    </DefaultFaultRule>
"@
    }

    return @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<ProxyEndpoint name="default">
    <PreFlow name="PreFlow">
        <Request>
$preFlowBlock
        </Request>
        <Response/>
    </PreFlow>
    <PostFlow name="PostFlow">
        <Request/>
        <Response>
$postFlowBlock
        </Response>
    </PostFlow>$corsFlow$faultRulesBlock
    <HTTPProxyConnection>
        <BasePath>$BasePath</BasePath>
        <VirtualHost>$VHost</VirtualHost>
    </HTTPProxyConnection>
    <RouteRule name="default">
        <TargetEndpoint>default</TargetEndpoint>
    </RouteRule>
    <RouteRule name="NoRoute">
        <Condition>request.verb == "OPTIONS"</Condition>
    </RouteRule>
</ProxyEndpoint>
"@
}

function New-TargetEndpointXml {
    param([string]$Name, [string]$TargetUrl)
    return @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<TargetEndpoint name="default">
    <PreFlow name="PreFlow"><Request/><Response/></PreFlow>
    <PostFlow name="PostFlow"><Request/><Response/></PostFlow>
    <Flows/>
    <HTTPTargetConnection>
        <URL>$TargetUrl</URL>
        <Properties>
            <Property name="connect.timeout.millis">30000</Property>
            <Property name="io.timeout.millis">55000</Property>
        </Properties>
    </HTTPTargetConnection>
</TargetEndpoint>
"@
}

# ═════════════════════════════════════════════════════════════════════
#  SHARED FLOW BUNDLE XML
# ═════════════════════════════════════════════════════════════════════

function New-SharedFlowBundleXml {
    param([string]$Name, [string]$Description, [string[]]$PolicyNames)
    $pNodes = if ($PolicyNames) {
        ($PolicyNames | ForEach-Object { "        <Policy>$_</Policy>" }) -join "`n"
    } else { "" }
    return @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<SharedFlowBundle revision="1" name="$Name">
    <DisplayName>$Name</DisplayName>
    <Description>$Description</Description>
    <Policies>
$pNodes
    </Policies>
    <SharedFlows><SharedFlow>default</SharedFlow></SharedFlows>
</SharedFlowBundle>
"@
}

function New-SharedFlowDefaultXml {
    param([string[]]$PolicyNames)
    $steps = if ($PolicyNames) {
        ($PolicyNames | ForEach-Object { "    <Step><Name>$_</Name></Step>" }) -join "`n"
    } else { "    <Step/>" }
    return @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<SharedFlow name="default">
$steps
</SharedFlow>
"@
}

# ═════════════════════════════════════════════════════════════════════
#  MAVEN POM TEMPLATES
# ═════════════════════════════════════════════════════════════════════

function New-RootPomXml {
    param([string]$Org, [string]$Env)
    $d = $script:Defaults
    return @"
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.apigee</groupId>
    <artifactId>apigee-parent</artifactId>
    <version>1.0-SNAPSHOT</version>
    <packaging>pom</packaging>

    <properties>
        <apigee.org>$Org</apigee.org>
        <apigee.env>$Env</apigee.env>
        <apigee.hosturl>$($d.HostUrl)</apigee.hosturl>
        <apigee.apitype>configbundle</apigee.apitype>
        <apigee.options>override</apigee.options>
        <apigee.config.options>update</apigee.config.options>
        <apigee.config.dir>`${project.basedir}</apigee.config.dir>
        <apigee.bearer>`${APIGEE_TOKEN}</apigee.bearer>
    </properties>

    <profiles>
        <profile><id>eval</id><properties><apigee.env>eval</apigee.env></properties></profile>
        <profile><id>dev</id><properties><apigee.env>dev</apigee.env></properties></profile>
        <profile><id>prod</id><properties><apigee.env>prod</apigee.env></properties></profile>
    </profiles>

    <build>
        <plugins>
            <plugin>
                <groupId>io.apigee.build-tools.enterprise4g</groupId>
                <artifactId>apigee-edge-maven-plugin</artifactId>
                <version>$($d.MavenPluginVer)</version>
                <executions>
                    <execution><id>configure-bundle</id><phase>package</phase><goals><goal>configure</goal></goals></execution>
                    <execution><id>deploy-bundle</id><phase>install</phase><goals><goal>deploy</goal></goals></execution>
                </executions>
            </plugin>
            <plugin>
                <groupId>com.apigee.edge.config</groupId>
                <artifactId>apigee-config-maven-plugin</artifactId>
                <version>$($d.ConfigPluginVer)</version>
                <executions>
                    <execution><id>create-config-apiproduct</id><phase>install</phase><goals><goal>apiproducts</goal></goals></execution>
                    <execution><id>create-config-developer</id><phase>install</phase><goals><goal>developers</goal></goals></execution>
                    <execution><id>create-config-developerapps</id><phase>install</phase><goals><goal>apps</goal></goals></execution>
                </executions>
            </plugin>
        </plugins>
    </build>
</project>
"@
}

function New-ChildPomXml {
    param([string]$ArtifactId, [string]$RelativePath = "../../pom.xml")
    return @"
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
    <modelVersion>4.0.0</modelVersion>
    <parent>
        <groupId>com.apigee</groupId>
        <artifactId>apigee-parent</artifactId>
        <version>1.0-SNAPSHOT</version>
        <relativePath>$RelativePath</relativePath>
    </parent>
    <artifactId>$ArtifactId</artifactId>
    <packaging>pom</packaging>
    <name>$ArtifactId</name>
</project>
"@
}

# ═════════════════════════════════════════════════════════════════════
#  edge.json BUILDER
# ═════════════════════════════════════════════════════════════════════

function New-EdgeJson {
    param([hashtable]$Config)

    $products = @($Config.api_products | ForEach-Object {
        @{
            name           = $_.name
            displayName    = $_.display_name ?? $_.name
            description    = $_.description ?? ""
            approvalType   = $_.approval_type ?? "auto"
            attributes     = @(@{ name = "access"; value = $_.access ?? "public" })
            environments   = @($_.environments ?? @($Config.env ?? "eval"))
            proxies        = @($_.proxies ?? @())
            quota          = [string]($_.quota ?? 100)
            quotaInterval  = [string]($_.quota_interval ?? 1)
            quotaTimeUnit  = $_.quota_time_unit ?? "minute"
            scopes         = @($_.scopes ?? @())
        }
    })

    $developers = @($Config.developers | ForEach-Object {
        @{
            email     = $_.email
            firstName = $_.first_name ?? ""
            lastName  = $_.last_name ?? ""
            userName  = $_.username ?? ($_.email -split "@")[0]
        }
    })

    $devApps = @{}
    foreach ($dev in $Config.developers) {
        $devApps[$dev.email] = @($Config.apps |
            Where-Object { $_.developer_email -eq $dev.email } |
            ForEach-Object {
                @{
                    name        = $_.name
                    apiProducts = @($_.api_products ?? @())
                    callbackUrl = $_.callback_url ?? ""
                    attributes  = @(@{ name = "DisplayName"; value = $_.display_name ?? $_.name })
                }
            })
    }

    return @{ orgConfig = @{ apiProducts = $products; developers = $developers; developerApps = $devApps } } |
           ConvertTo-Json -Depth 10
}

# ═════════════════════════════════════════════════════════════════════
#  TOKEN HELPER
# ═════════════════════════════════════════════════════════════════════

function Get-ApigeeToken {
    param([switch]$UseGcloud)
    if ($UseGcloud) {
        $token = & gcloud auth print-access-token 2>$null
        if ($LASTEXITCODE -ne 0) { throw "gcloud auth failed" }
        return $token.Trim()
    }
    if ($env:GOOGLE_APPLICATION_CREDENTIALS) {
        return (& gcloud auth application-default print-access-token 2>$null).Trim()
    }
    throw "Set GOOGLE_APPLICATION_CREDENTIALS or use -UseGcloud"
}

Write-Host "config.ps1 loaded" -ForegroundColor DarkGray
