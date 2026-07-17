#!/usr/bin/env python3
"""
Generates edge.json from config/defaults.yaml.
edge.json is consumed by apigee-config-maven-plugin to deploy
API products, developers, and apps.
Use --force to overwrite existing file.
"""

import os
import sys
import json
import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FORCE = "--force" in sys.argv


def load_config():
    with open(os.path.join(ROOT, "config", "defaults.yaml")) as f:
        return yaml.safe_load(f)


def write_file(path, content):
    if os.path.exists(path) and not FORCE:
        print(f"  [SKIP] {os.path.relpath(path, ROOT)} (exists, use --force)")
        return
    with open(path, "w", newline="\n") as f:
        f.write(content)
    print(f"  [OK]   {os.path.relpath(path, ROOT)}")


def build_edge_json(cfg):
    env_name = cfg.get("env", "eval")

    # API Products
    products = []
    for p in cfg.get("api_products", []):
        products.append({
            "name": p["name"],
            "displayName": p.get("display_name", p["name"]),
            "description": p.get("description", ""),
            "approvalType": p.get("approval_type", "auto"),
            "attributes": [
                {"name": "access", "value": p.get("access", "public")}
            ],
            "environments": p.get("environments", [env_name]),
            "proxies": p.get("proxies", []),
            "quota": str(p.get("quota", 100)),
            "quotaInterval": str(p.get("quota_interval", 1)),
            "quotaTimeUnit": p.get("quota_time_unit", "minute"),
            "scopes": p.get("scopes", []),
        })

    # Developers
    developers = []
    for d in cfg.get("developers", []):
        developers.append({
            "email": d["email"],
            "firstName": d.get("first_name", ""),
            "lastName": d.get("last_name", ""),
            "userName": d.get("username", d["email"].split("@")[0]),
        })

    # Developer Apps (grouped by developer email)
    dev_apps = {}
    for d in cfg.get("developers", []):
        apps = []
        for a in cfg.get("apps", []):
            if a.get("developer_email") == d["email"]:
                apps.append({
                    "name": a["name"],
                    "apiProducts": a.get("api_products", []),
                    "callbackUrl": a.get("callback_url", ""),
                    "attributes": [
                        {"name": "DisplayName", "value": a.get("display_name", a["name"])}
                    ],
                })
        dev_apps[d["email"]] = apps

    edge = {
        "orgConfig": {
            "apiProducts": products,
            "developers": developers,
            "developerApps": dev_apps,
        }
    }

    return json.dumps(edge, indent=2) + "\n"


def main():
    cfg = load_config()
    print("\n==> Generating edge.json (API Products, Developers, Apps)")

    products = cfg.get("api_products", [])
    developers = cfg.get("developers", [])
    apps = cfg.get("apps", [])

    edge_path = os.path.join(ROOT, "edge.json")
    write_file(edge_path, build_edge_json(cfg))

    print(f"\n    Products:   {len(products)}")
    print(f"    Developers: {len(developers)}")
    print(f"    Apps:       {len(apps)}")
    print(f"\n==> Done.\n")


if __name__ == "__main__":
    main()
