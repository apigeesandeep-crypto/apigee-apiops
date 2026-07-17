#!/usr/bin/env python3
"""
Generates Shared Flow XML files from config/defaults.yaml.
Use --force to overwrite existing files.
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
#  SHARED FLOW POLICY TEMPLATES
# ═══════════════════════════════════════════════════════════════

POLICY_TEMPLATES = {
    "verify-api-key": lambda name: textwrap.dedent(f"""\
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <VerifyAPIKey name="{name}">
            <DisplayName>{name}</DisplayName>
            <APIKey ref="request.header.x-api-key"/>
        </VerifyAPIKey>
    """),

    "json-threat-protection": lambda name: textwrap.dedent(f"""\
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <JSONThreatProtection name="{name}">
            <DisplayName>{name}</DisplayName>
            <Source>request</Source>
            <ArrayElementCount>20</ArrayElementCount>
            <ContainerDepth>10</ContainerDepth>
            <ObjectEntryCount>25</ObjectEntryCount>
            <ObjectEntryNameLength>50</ObjectEntryNameLength>
            <StringValueLength>500</StringValueLength>
        </JSONThreatProtection>
    """),

    "cors-preflight": lambda name: textwrap.dedent(f"""\
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <RaiseFault name="{name}">
            <DisplayName>{name}</DisplayName>
            <FaultResponse>
                <Set>
                    <Headers>
                        <Header name="Access-Control-Allow-Origin">*</Header>
                        <Header name="Access-Control-Allow-Methods">GET, POST, PUT, DELETE, OPTIONS</Header>
                        <Header name="Access-Control-Allow-Headers">Content-Type, Authorization, x-api-key</Header>
                        <Header name="Access-Control-Max-Age">3600</Header>
                    </Headers>
                    <Payload contentType="application/json">{{}}</Payload>
                    <StatusCode>200</StatusCode>
                    <ReasonPhrase>OK</ReasonPhrase>
                </Set>
            </FaultResponse>
            <IgnoreUnresolvedVariables>true</IgnoreUnresolvedVariables>
        </RaiseFault>
    """),

    "cors-headers": lambda name: textwrap.dedent(f"""\
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <AssignMessage name="{name}">
            <DisplayName>{name}</DisplayName>
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
    """),

    "message-logging": lambda name: textwrap.dedent(f"""\
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <MessageLogging name="{name}">
            <DisplayName>{name}</DisplayName>
            <CloudLogging>
                <LogName>projects/{{organization.name}}/logs/apigee-api-logs</LogName>
                <Message contentType="application/json">{{
          "proxy": "{{apiproxy.name}}",
          "verb": "{{request.verb}}",
          "uri": "{{request.uri}}",
          "status": "{{response.status.code}}",
          "clientIp": "{{client.ip}}",
          "latency": "{{target.received.end.timestamp - target.sent.start.timestamp}}"
        }}</Message>
                <Labels>
                    <Label><Key>proxy</Key><Value>{{apiproxy.name}}</Value></Label>
                    <Label><Key>env</Key><Value>{{environment.name}}</Value></Label>
                </Labels>
            </CloudLogging>
            <logLevel>INFO</logLevel>
        </MessageLogging>
    """),
}


# ═══════════════════════════════════════════════════════════════
#  BUNDLE TEMPLATES
# ═══════════════════════════════════════════════════════════════

def sharedflow_bundle_xml(name, description, policy_names):
    policies = "\n".join(f"        <Policy>{p}</Policy>" for p in policy_names)
    return textwrap.dedent(f"""\
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <SharedFlowBundle revision="1" name="{name}">
            <DisplayName>{name}</DisplayName>
            <Description>{description}</Description>
            <Policies>
        {policies}
            </Policies>
            <SharedFlows>
                <SharedFlow>default</SharedFlow>
            </SharedFlows>
        </SharedFlowBundle>
    """)


def sharedflow_default_xml(policy_names):
    if policy_names:
        steps = "\n".join(f"    <Step><Name>{p}</Name></Step>" for p in policy_names)
    else:
        steps = "    <Step/>"
    return textwrap.dedent(f"""\
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <SharedFlow name="default">
        {steps}
        </SharedFlow>
    """)


# ═══════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════

def generate_sharedflow(flow):
    name = flow["name"]
    description = flow.get("description", name)
    policies = flow.get("policies", [])
    base = os.path.join(ROOT, "sharedflows", name, "sharedflowbundle")

    policy_names = [p["name"] for p in policies]

    print(f"\n  SharedFlow: {name} ({len(policy_names)} policies)")

    write_file(
        os.path.join(base, f"{name}.xml"),
        sharedflow_bundle_xml(name, description, policy_names),
    )
    write_file(
        os.path.join(base, "sharedflows", "default.xml"),
        sharedflow_default_xml(policy_names),
    )

    for pol in policies:
        template_fn = POLICY_TEMPLATES.get(pol["type"])
        if template_fn:
            write_file(
                os.path.join(base, "policies", f"{pol['name']}.xml"),
                template_fn(pol["name"]),
            )
        else:
            print(f"  [WARN] Unknown policy type: {pol['type']}")


def main():
    cfg = load_config()
    print("\n==> Generating Shared Flow files")

    for flow in cfg.get("shared_flows", []):
        generate_sharedflow(flow)

    print(f"\n==> Done. {len(cfg.get('shared_flows', []))} shared flows generated.\n")


if __name__ == "__main__":
    main()
