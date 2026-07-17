# Apigee APIops — Automated API Proxy Management

Scaffolding, linting, and CI/CD deployment of Apigee X artifacts using Maven plugins and GitHub Actions with Workload Identity Federation (WIF).

---

## What Gets Deployed

| Artifact | Source | Trigger |
|----------|--------|---------|
| **Shared Flows** | `sharedflows/<name>/` | Push to `sharedflows/**` |
| **API Proxies** | `apiproxies/<name>/` | Push to `apiproxies/**` |
| **API Products** | `edge.json` | Push to `edge.json` |
| **Developers** | `edge.json` | Push to `edge.json` |
| **Apps** | `edge.json` | Push to `edge.json` |

---

## Project Structure

```
apigee-apiops/
├── apiproxies/
│   └── <proxy-name>/
│       ├── pom.xml
│       └── apiproxy/
│           ├── <proxy-name>.xml
│           ├── proxies/default.xml
│           ├── targets/default.xml
│           ├── policies/
│           │   ├── SA-SpikeArrest.xml
│           │   ├── OA-VerifyAccessToken.xml
│           │   ├── QU-RateLimit.xml
│           │   ├── FC-Security.xml
│           │   ├── FC-CORS.xml
│           │   ├── AM-RemoveAuthHeader.xml
│           │   ├── JS-ThreatProtection.xml
│           │   ├── RF-InvalidApiKey.xml
│           │   ├── RF-QuotaViolation.xml
│           │   └── RF-ThreatDetected.xml
│           └── resources/jsc/
│               └── threat-protection.js
├── sharedflows/
│   └── <flow-name>/
│       ├── pom.xml
│       └── sharedflowbundle/
│           ├── <flow-name>.xml
│           ├── policies/
│           └── sharedflows/default.xml
├── config/
│   └── defaults.yaml
├── scripts/
│   ├── config.ps1
│   ├── scaffold.ps1
│   └── deploy.ps1
├── edge.json
├── pom.xml
├── .apigeelintrc
├── .gitignore
└── .github/workflows/
    ├── ci-lint.yaml
    ├── deploy-sharedflows.yaml
    ├── deploy-proxies.yaml
    └── deploy-config.yaml
```

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| PowerShell | 7.x+ | `sudo apt-get install -y powershell` |
| Maven | 3.6+ | `sudo apt-get install -y maven` |
| JDK | 11+ | `sudo apt-get install -y openjdk-11-jdk` |
| Node.js | 16+ | Pre-installed in Codespaces |
| apigeelint | latest | `npm install -g apigeelint` |
| gcloud CLI | latest | `sudo apt-get install -y google-cloud-cli` |
| powershell-yaml | latest | `pwsh -c "Install-Module powershell-yaml -Scope CurrentUser -Force"` |

---

## Quick Start

### 1. Clone

```bash
git clone https://github.com/YOUR-USER/apigee-apiops.git
cd apigee-apiops
```

### 2. Configure

Edit `config/defaults.yaml` with your values:

```yaml
org: "your-gcp-project-id"     # GCP project ID
env: "eval"                     # Apigee environment

api_proxies:
  - name: my-api
    base_path: /my-api/v1
    target_url: https://my-backend.example.com
    ...

developers:
  - email: you@example.com
    ...
```

### 3. Scaffold

```bash
pwsh scripts/scaffold.ps1
```

### 4. Lint

```bash
apigeelint -s apiproxies/my-api/apiproxy -f table.js --profile apigeex
```

### 5. Deploy

```bash
# Via gcloud (local)
gcloud auth login
pwsh scripts/deploy.ps1 -Target all -UseGcloud

# Or push to GitHub (CI/CD)
git add . && git commit -m "Initial scaffold" && git push origin main
```

---

## Policy Flow (Per Proxy)

Each scaffolded proxy includes the following policy chain:

```
Client Request
  │
  ├── PreFlow (Request)
  │     1. SA-SpikeArrest          → Rate limiting (e.g. 30/sec)
  │     2. OA-VerifyAccessToken    → OAuth 2.0 token validation
  │     3. QU-RateLimit            → Quota enforcement (e.g. 100/min)
  │     4. FC-Security             → Shared flow: JSON + regex threat protection
  │     5. JS-ThreatProtection     → SQL injection / XSS blocking
  │     6. AM-RemoveAuthHeader     → Strip auth headers before backend
  │
  ├── Target
  │     Backend HTTP call (30s connect, 55s IO timeout)
  │
  ├── PostFlow (Response)
  │     7. FC-CORS                 → Shared flow: CORS response headers
  │
  └── FaultRules
        RF-InvalidApiKey           → 401 JSON error
        RF-QuotaViolation          → 429 JSON error
        RF-ThreatDetected          → 400 JSON error
```

---

## Shared Flows

| Flow | Purpose | Policies |
|------|---------|----------|
| `sf-security` | Common security checks | OAuth verify, JSON threat protection, regex threat protection |
| `sf-cors` | CORS preflight + headers | CORS preflight (OPTIONS → 200), CORS response headers |
| `sf-logging` | Request/response logging | Cloud Logging (Stackdriver) message logging |

---

## Scripts

### `scripts/scaffold.ps1`

Generates the full project tree from `config/defaults.yaml`.

```bash
# Default config
pwsh scripts/scaffold.ps1

# Custom config
pwsh scripts/scaffold.ps1 -ConfigPath ./config/custom.yaml
```

### `scripts/deploy.ps1`

Deploys artifacts via Maven.

```bash
# Deploy everything (shared flows → proxies → config)
pwsh scripts/deploy.ps1 -Target all -UseGcloud

# Deploy single proxy
pwsh scripts/deploy.ps1 -Target proxy -Name petstore-api -UseGcloud

# Deploy single shared flow
pwsh scripts/deploy.ps1 -Target sharedflow -Name sf-security -UseGcloud

# Deploy config only (products, developers, apps)
pwsh scripts/deploy.ps1 -Target config -UseGcloud

# Dry run (preview commands)
pwsh scripts/deploy.ps1 -Target all -UseGcloud -DryRun
```

### `scripts/config.ps1`

Shared helper functions and XML/JSON template builders. Dot-sourced by the other scripts — not run directly.

---

## CI/CD Pipelines

### Workflows

| Workflow | File | Trigger | What it does |
|----------|------|---------|--------------|
| **Lint** | `ci-lint.yaml` | PR to `main` | Runs apigeelint on all proxies and shared flows |
| **Deploy Shared Flows** | `deploy-sharedflows.yaml` | Push to `sharedflows/**` | Deploys only changed shared flows |
| **Deploy Proxies** | `deploy-proxies.yaml` | Push to `apiproxies/**` | Deploys only changed proxies |
| **Deploy Config** | `deploy-config.yaml` | Push to `edge.json` | Updates API products, developers, apps |

### Change Detection

Pipelines use `git diff` to detect which artifacts changed and only deploy those:

```
Push: modified apiproxies/petstore-api/apiproxy/policies/QU-RateLimit.xml
  → deploy-proxies.yaml runs
  → Detects: petstore-api changed
  → Deploys: only petstore-api (not weather-api)
```

### Required GitHub Variables

Set in **Settings → Secrets and variables → Actions → Variables**:

| Variable | Description | Example |
|----------|-------------|---------|
| `APIGEE_ORG` | GCP project ID | `my-project-123` |
| `APIGEE_ENV` | Apigee environment | `eval` |
| `WIF_PROVIDER` | Workload Identity Federation provider | `projects/123/locations/global/workloadIdentityPools/pool/providers/github` |
| `SA_EMAIL` | Service account email | `apigee-sa@my-project.iam.gserviceaccount.com` |

### Service Account Permissions

The SA needs these IAM roles on the GCP project:

```
roles/apigee.admin          # Deploy proxies and shared flows
roles/apigee.apiAdminV2     # Manage products, developers, apps
```

---

## First-Time Deployment Order

On initial setup, deploy in this order to avoid dependency issues (products reference proxies):

```bash
# 1. Shared Flows (no dependencies)
git add sharedflows/ pom.xml .apigeelintrc .gitignore scripts/ config/
git commit -m "Add shared flows and scaffolding"
git push origin main
# Wait for pipeline to complete

# 2. API Proxies (reference shared flows)
git add apiproxies/
git commit -m "Add API proxies with policies"
git push origin main
# Wait for pipeline to complete

# 3. Config (products reference deployed proxies)
git add edge.json
git commit -m "Add API products, developers, and apps"
git push origin main
# Wait for pipeline to complete

# 4. Workflows (for future automated deployments)
git add .github/
git commit -m "Add CI/CD workflows"
git push origin main
```

---

## Day-to-Day Operations

### Modify an existing proxy

```bash
nano apiproxies/petstore-api/apiproxy/policies/QU-RateLimit.xml
# Change allow_count from 100 to 200

apigeelint -s apiproxies/petstore-api/apiproxy -f table.js --profile apigeex

git add apiproxies/petstore-api/
git commit -m "Increase petstore quota to 200/min"
git push origin main
# → Only deploy-proxies.yaml triggers, only petstore-api deploys
```

### Add a new proxy

```bash
# 1. Add entry to config/defaults.yaml
# 2. Re-run scaffold
pwsh scripts/scaffold.ps1

# 3. Fix any lint issues
apigeelint -s apiproxies/new-api/apiproxy -f table.js --profile apigeex

# 4. Push
git add apiproxies/new-api/
git commit -m "Add new-api proxy"
git push origin main
```

### Update API products or apps

```bash
# Edit edge.json directly or update defaults.yaml and re-scaffold
nano edge.json

git add edge.json
git commit -m "Add new API product"
git push origin main
# → Only deploy-config.yaml triggers
```

---

## Lint Rules

Uses `apigeelint` with the `apigeex` profile (Apigee X/hybrid). Configuration in `.apigeelintrc`:

```json
{
  "excluded": {},
  "maxWarnings": -1,
  "profile": "apigeex"
}
```

Common rules enforced:

| Rule | ID | Severity |
|------|----|----------|
| Unconditional RouteRule must be last | PD003 | Error |
| No duplicate RouteRule names | CC008 | Error |
| No VirtualHost in Apigee X | PD005 | Warning |
| Standard policy naming prefixes | PO007 | Warning |
| Target should use SSLInfo | TD012 | Warning |

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `Plugin not found` in Maven | Ensure `<pluginRepositories>` block is in `pom.xml` |
| `401 Unauthorized` in pipeline | Check WIF provider config and SA permissions |
| `403 Forbidden` | Add `roles/apigee.admin` to the service account |
| `404 org not found` | Verify `APIGEE_ORG` variable matches GCP project ID |
| `409 already exists` | Normal — artifact is updated in place |
| `apigeelint: command not found` | `npm install -g apigeelint` |
| `pwsh: command not found` | `sudo apt-get install -y powershell` |
| Scaffold generates duplicates | Delete generated folders first: `rm -rf apiproxies/ sharedflows/` then re-scaffold |

---

## GCP Setup Reference

### Workload Identity Federation (WIF)

```bash
# Create pool
gcloud iam workload-identity-pools create "github-pool" \
  --location="global" \
  --display-name="GitHub Actions Pool"

# Create provider
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --display-name="GitHub Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository=='YOUR-USER/apigee-apiops'" \
  --issuer-uri="https://token.actions.githubusercontent.com"

# Allow SA impersonation
gcloud iam service-accounts add-iam-policy-binding "apigee-sa@PROJECT.iam.gserviceaccount.com" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/PROJECT_NUM/locations/global/workloadIdentityPools/github-pool/attribute.repository/YOUR-USER/apigee-apiops"
```

### Service Account

```bash
# Create SA
gcloud iam service-accounts create apigee-sa --display-name="Apigee Deployer"

# Grant roles
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:apigee-sa@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/apigee.admin"
```
