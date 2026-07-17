#!/usr/bin/env python3
"""
Generates API proxy XML files from config/defaults.yaml.
Creates: proxy descriptor, ProxyEndpoint, TargetEndpoint, all policies.
Use --force to overwrite existing files. Default: skip existing.
"""

import os
import sys
import yaml
import textwrap

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FORCE = "--force" in sys.argv


def load_config():
    with open(os.path.join(ROOT, "config", "defaults.yaml")) as f:
        return yaml.safe_load(f)


def write_file(path, content):
    if os.path.exists(path) and not FORCE:
        print(f"  [SKIP] {os.path.relpath(path, ROOT)} (exists, use --force)")
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="\n") as f:
        f.write(content)
    print(f"  [OK]   {os.path.relpath(path, ROOT)}")


# ═══════════════════════════════════════════════════════════════
#  POLICY TEMPLATES
# ═══════════════════════════════════════════════════════════════

def spike_arrest_xml(rate="30ps"):
    return textwrap.dedent(f"""\
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <SpikeArrest name="SA-SpikeArrest">
            <DisplayName>SA-SpikeArrest</DisplayName>
            <Rate>{rate}</Rate>
            <Identifier ref="request.header.x-api-key"/>
            <UseEffectiveCount>true</UseEffectiveCount>
        </SpikeArrest>
    """)


def verify_api_key_xml():
    return textwrap.dedent("""\
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <VerifyAPIKey name="VA-VerifyKey">
            <DisplayName>VA-VerifyKey</DisplayName>
            <APIKey ref="request.header.x-api-key"/>
        </VerifyAPIKey>
    """)


def quota_xml(allow_count=100, interval=1, time_unit="minute"):
    return textwrap.dedent(f"""\
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Quota name="QU-RateLimit" type="calendar">
            <DisplayName>QU-RateLimit</DisplayName>
            <Allow count="{allow_count}" countRef="verifyapikey.VA-VerifyKey.apiproduct.developer.quota.limit"/>
            <Interval ref="verifyapikey.VA-VerifyKey.apiproduct.developer.quota.interval">{interval}</Interval>
            <TimeUnit ref="verifyapikey.VA-VerifyKey.apiproduct.developer.quota.timeunit">{time_unit}</TimeUnit>
            <Distributed>true</Distributed>
            <Synchronous>true</Synchronous>
            <StartTime>2024-01-01 00:00:00</StartTime>
            <Identifier ref="request.header.x-api-key"/>
        </Quota>
    """)


def flow_callout_xml(name, shared_flow_bundle):
    return textwrap.dedent(f"""\
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <FlowCallout name="{name}">
            <DisplayName>{name}</DisplayName>
            <SharedFlowBundle>{shared_flow_bundle}</SharedFlowBundle>
        </FlowCallout>
    """)


def remove_auth_header_xml():
    return textwrap.dedent("""\
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <AssignMessage name="AM-RemoveAuthHeader">
            <DisplayName>AM-RemoveAuthHeader</DisplayName>
            <Remove>
                <Headers>
                    <Header name="Authorization"/>
                    <Header name="x-api-key"/>
                </Headers>
            </Remove>
            <AssignTo createNew="false" transport="http" type="request"/>
            <IgnoreUnresolvedVariables>true</IgnoreUnresolvedVariables>
        </AssignMessage>
    """)


def js_threat_protection_xml():
    return textwrap.dedent("""\
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Javascript name="JS-ThreatProtection" timeLimit="200">
            <DisplayName>JS-ThreatProtection</DisplayName>
            <ResourceURL>jsc://threat-protection.js</ResourceURL>
        </Javascript>
    """)


def threat_protection_js():
    return textwrap.dedent("""\
        var payload = context.getVariable("request.content") || "";
        var uri = context.getVariable("request.uri") || "";
        var check = payload + uri;

        var sqlPatterns = /(\\b(SELECT|INSERT|UPDATE|DELETE|DROP|UNION|ALTER|CREATE|EXEC)\\b)/gi;
        var xssPatterns = /(<script|javascript:|on\\w+\\s*=)/gi;

        if (sqlPatterns.test(check) || xssPatterns.test(check)) {
            throw new Error("ThreatDetected");
        }
    """)


def raise_fault_xml(name, status_code, reason, message):
    return textwrap.dedent(f"""\
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <RaiseFault name="RF-{name}">
            <DisplayName>RF-{name}</DisplayName>
            <FaultResponse>
                <Set>
                    <Headers>
                        <Header name="Content-Type">application/json</Header>
                    </Headers>
                    <Payload contentType="application/json">{{
          "error": {{
            "code": {status_code},
            "status": "{reason}",
            "message": "{message}"
          }}
        }}</Payload>
                    <StatusCode>{status_code}</StatusCode>
                    <ReasonPhrase>{reason}</ReasonPhrase>
                </Set>
            </FaultResponse>
            <IgnoreUnresolvedVariables>true</IgnoreUnresolvedVariables>
        </RaiseFault>
    """)


# ═══════════════════════════════════════════════════════════════
#  PROXY BUNDLE TEMPLATES
# ═══════════════════════════════════════════════════════════════

def proxy_descriptor_xml(name, base_path, description, policy_names):
    policies = "\n".join(f"        <Policy>{p}</Policy>" for p in policy_names)
    return textwrap.dedent(f"""\
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <APIProxy revision="1" name="{name}">
            <DisplayName>{name}</DisplayName>
            <Description>{description}</Description>
            <BasePaths>{base_path}</BasePaths>
            <Policies>
        {policies}
            </Policies>
            <ProxyEndpoints>
                <ProxyEndpoint>default</ProxyEndpoint>
            </ProxyEndpoints>
            <TargetEndpoints>
                <TargetEndpoint>default</TargetEndpoint>
            </TargetEndpoints>
            <Resources/>
        </APIProxy>
    """)


def proxy_endpoint_xml(name, base_path, pol_cfg, fault_rules):
    # PreFlow request steps
    pre_steps = []
    if pol_cfg.get("spike_arrest"):
        pre_steps.append("                <Step><Name>SA-SpikeArrest</Name></Step>")
    if pol_cfg.get("verify_api_key"):
        pre_steps.append("                <Step><Name>VA-VerifyKey</Name></Step>")
    if pol_cfg.get("quota"):
        pre_steps.append("                <Step><Name>QU-RateLimit</Name></Step>")
    if pol_cfg.get("security_flow"):
        pre_steps.append("                <Step><Name>FC-Security</Name></Step>")
    if pol_cfg.get("threat_protection"):
        pre_steps.append("                <Step><Name>JS-ThreatProtection</Name></Step>")
    if pol_cfg.get("remove_auth_header"):
        pre_steps.append("                <Step><Name>AM-RemoveAuthHeader</Name></Step>")
    pre_flow_block = "\n".join(pre_steps)

    # PostFlow response steps
    post_steps = []
    if pol_cfg.get("cors"):
        post_steps.append("                <Step><Name>FC-CORS</Name></Step>")
    post_flow_block = "\n".join(post_steps)

    # CORS preflight flow
    cors_flow = ""
    if pol_cfg.get("cors"):
        cors_flow = textwrap.dedent("""\
            <Flows>
                <Flow name="OptionsPreFlight">
                    <Description>CORS preflight</Description>
                    <Request/>
                    <Response>
                        <Step><Name>FC-CORS</Name></Step>
                    </Response>
                    <Condition>request.verb == "OPTIONS"</Condition>
                </Flow>
            </Flows>""")
    else:
        cors_flow = "    <Flows/>"

    # Fault rules
    fault_block = ""
    if fault_rules:
        rules = []
        for fr in fault_rules:
            rules.append(textwrap.dedent(f"""\
                <FaultRule name="{fr['name']}">
                    <Condition>{fr['condition']}</Condition>
                    <Step><Name>RF-{fr['name']}</Name></Step>
                </FaultRule>"""))
        fault_block = (
            "    <FaultRules>\n"
            + "\n".join("        " + line for r in rules for line in r.strip().split("\n"))
            + "\n    </FaultRules>\n"
            + "    <DefaultFaultRule name=\"DefaultFault\">\n"
            + "        <AlwaysEnforce>true</AlwaysEnforce>\n"
            + "    </DefaultFaultRule>"
        )

    return textwrap.dedent(f"""\
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <ProxyEndpoint name="default">
            <PreFlow name="PreFlow">
                <Request>
        {pre_flow_block}
                </Request>
                <Response/>
            </PreFlow>
            <PostFlow name="PostFlow">
                <Request/>
                <Response>
        {post_flow_block}
                </Response>
            </PostFlow>
            {cors_flow}
        {fault_block}
            <HTTPProxyConnection>
                <BasePath>{base_path}</BasePath>
            </HTTPProxyConnection>
            <RouteRule name="NoRoute">
                <Condition>request.verb == "OPTIONS"</Condition>
            </RouteRule>
            <RouteRule name="default">
                <TargetEndpoint>default</TargetEndpoint>
            </RouteRule>
        </ProxyEndpoint>
    """)


def target_endpoint_xml(name, target_url):
    return textwrap.dedent(f"""\
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <TargetEndpoint name="default">
            <PreFlow name="PreFlow"><Request/><Response/></PreFlow>
            <PostFlow name="PostFlow"><Request/><Response/></PostFlow>
            <Flows/>
            <HTTPTargetConnection>
                <URL>{target_url}</URL>
                <Properties>
                    <Property name="connect.timeout.millis">30000</Property>
                    <Property name="io.timeout.millis">55000</Property>
                </Properties>
            </HTTPTargetConnection>
        </TargetEndpoint>
    """)


# ═══════════════════════════════════════════════════════════════
#  MAIN — GENERATE ALL PROXY FILES
# ═══════════════════════════════════════════════════════════════

def generate_proxy(proxy):
    name = proxy["name"]
    base_path = proxy.get("base_path", f"/{name}")
    target_url = proxy.get("target_url", "https://httpbin.org/anything")
    description = proxy.get("description", name)
    pol_cfg = proxy.get("policies", {})
    fault_rules = proxy.get("fault_rules", [])

    base = os.path.join(ROOT, "apiproxies", name, "apiproxy")

    # Collect policy names and files
    policy_files = {}
    policy_names = []

    if pol_cfg.get("spike_arrest"):
        policy_names.append("SA-SpikeArrest")
        policy_files["SA-SpikeArrest.xml"] = spike_arrest_xml(
            pol_cfg["spike_arrest"].get("rate", "30ps")
        )

    if pol_cfg.get("verify_api_key"):
        policy_names.append("VA-VerifyKey")
        policy_files["VA-VerifyKey.xml"] = verify_api_key_xml()

    if pol_cfg.get("quota"):
        policy_names.append("QU-RateLimit")
        q = pol_cfg["quota"]
        policy_files["QU-RateLimit.xml"] = quota_xml(
            q.get("allow_count", 100),
            q.get("interval", 1),
            q.get("time_unit", "minute"),
        )

    if pol_cfg.get("security_flow"):
        policy_names.append("FC-Security")
        policy_files["FC-Security.xml"] = flow_callout_xml(
            "FC-Security", pol_cfg["security_flow"]
        )

    if pol_cfg.get("threat_protection"):
        policy_names.append("JS-ThreatProtection")
        policy_files["JS-ThreatProtection.xml"] = js_threat_protection_xml()

    if pol_cfg.get("remove_auth_header"):
        policy_names.append("AM-RemoveAuthHeader")
        policy_files["AM-RemoveAuthHeader.xml"] = remove_auth_header_xml()

    if pol_cfg.get("cors"):
        cors_flow = pol_cfg.get("cors_flow", "sf-cors")
        policy_names.append("FC-CORS")
        policy_files["FC-CORS.xml"] = flow_callout_xml("FC-CORS", cors_flow)

    for fr in fault_rules:
        rf_name = f"RF-{fr['name']}"
        policy_names.append(rf_name)
        policy_files[f"{rf_name}.xml"] = raise_fault_xml(
            fr["name"], fr["status_code"], fr["reason"], fr["message"]
        )

    print(f"\n  Proxy: {name} ({len(policy_names)} policies)")

    # Write files
    write_file(
        os.path.join(base, f"{name}.xml"),
        proxy_descriptor_xml(name, base_path, description, policy_names),
    )
    write_file(
        os.path.join(base, "proxies", "default.xml"),
        proxy_endpoint_xml(name, base_path, pol_cfg, fault_rules),
    )
    write_file(
        os.path.join(base, "targets", "default.xml"),
        target_endpoint_xml(name, target_url),
    )
    for fname, content in policy_files.items():
        write_file(os.path.join(base, "policies", fname), content)

    if pol_cfg.get("threat_protection"):
        write_file(
            os.path.join(base, "resources", "jsc", "threat-protection.js"),
            threat_protection_js(),
        )


def main():
    cfg = load_config()
    print("\n==> Generating API Proxy files")

    for proxy in cfg.get("api_proxies", []):
        generate_proxy(proxy)

    print(f"\n==> Done. {len(cfg.get('api_proxies', []))} proxies generated.\n")


if __name__ == "__main__":
    main()
