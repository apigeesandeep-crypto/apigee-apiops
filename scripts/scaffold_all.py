#!/usr/bin/env python3
"""
Runs all scaffold scripts in order.
Usage:
    python scripts/scaffold_all.py              # skip existing files
    python scripts/scaffold_all.py --force      # overwrite everything
"""

import subprocess
import sys
import os

SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))

SCRIPTS = [
    "create_structure.py",
    "generate_sharedflow.py",
    "generate_proxy.py",
    "generate_config.py",
    "generate_pom.py",
]

def main():
    extra_args = sys.argv[1:]
    print("=" * 50)
    print("  Apigee Full Scaffold")
    print("=" * 50)

    for script in SCRIPTS:
        path = os.path.join(SCRIPTS_DIR, script)
        print(f"\n{'─' * 50}")
        print(f"  Running: {script}")
        print(f"{'─' * 50}")
        result = subprocess.run(
            [sys.executable, path] + extra_args,
            cwd=os.path.dirname(SCRIPTS_DIR),
        )
        if result.returncode != 0:
            print(f"\n  [ERROR] {script} failed with exit code {result.returncode}")
            sys.exit(1)

    print(f"\n{'=' * 50}")
    print("  All scaffolding complete!")
    print(f"{'=' * 50}\n")


if __name__ == "__main__":
    main()
