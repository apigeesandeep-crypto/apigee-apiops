#!/usr/bin/env python3
"""
Creates folder structure for all Apigee artifacts.
Reads config/defaults.yaml and creates directories for proxies,
shared flows, and config. Skips existing folders.
"""

import os
import sys
import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def load_config():
    config_path = os.path.join(ROOT, "config", "defaults.yaml")
    with open(config_path) as f:
        return yaml.safe_load(f)

def create_dir(path):
    if os.path.exists(path):
        return
    os.makedirs(path, exist_ok=True)
    print(f"  [OK] Created: {os.path.relpath(path, ROOT)}")

def create_proxy_dirs(proxy_name):
    base = os.path.join(ROOT, "apiproxies", proxy_name, "apiproxy")
    for sub in ["proxies", "targets", "policies", "resources/jsc"]:
        create_dir(os.path.join(base, sub))

def create_sharedflow_dirs(flow_name):
    base = os.path.join(ROOT, "sharedflows", flow_name, "sharedflowbundle")
    for sub in ["policies", "sharedflows"]:
        create_dir(os.path.join(base, sub))

def main():
    cfg = load_config()
    print("\n==> Creating folder structure\n")

    for proxy in cfg.get("api_proxies", []):
        print(f"  Proxy: {proxy['name']}")
        create_proxy_dirs(proxy["name"])

    for flow in cfg.get("shared_flows", []):
        print(f"  SharedFlow: {flow['name']}")
        create_sharedflow_dirs(flow["name"])

    create_dir(os.path.join(ROOT, "config"))

    print("\n==> Folder structure complete.\n")

if __name__ == "__main__":
    main()
