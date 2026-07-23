# Apigee X CI/CD Toolkit

Automated scaffolding, linting, and deployment pipeline for Apigee X API proxies, shared flows, API products, developers, and apps — powered by Python, Maven, and GitHub Actions with Workload Identity Federation (WIF).

---

## Table of Contents

- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [GCP Setup](#gcp-setup)
- [Scaffolding](#scaffolding)
- [Configuration](#configuration)
- [Linting](#linting)
- [Deployment](#deployment)
- [GitHub Actions Workflows](#github-actions-workflows)
- [Maven POM Structure](#maven-pom-structure)
- [Adding New Proxies or Shared Flows](#adding-new-proxies-or-shared-flows)
- [Updating Existing Artifacts](#updating-existing-artifacts)
- [Troubleshooting](#troubleshooting)

---

## Project Structure

```
apigee-apiops/
├── .github/
│   └── workflows/
│       ├── deploy-sharedflows.yaml    # Deploy shared flows to Apigee
│       ├── deploy-proxies.yaml        # Deploy API proxies to Apigee
│       ├── deploy-config.yaml         # Deploy products, developers, apps
│       └── ci-lint.yaml               # PR lint checks
├── apiproxies/
│   ├── petstore-api/
│   │   ├── pom.xml                    # Child POM (parent → ../../pom.xml)
│   │   └── apiproxy/
│   │       ├── proxies/default.xml
│   │       ├── targets/default.xml
│   │       ├── policies/
│   │       │   ├── SA-SpikeArrest.xml
│   │       │   ├── VA-VerifyKey.xml
│   │       │   ├── QU-RateLimit.xml
│   │       │   ├── FC-Security.xml
│   │       │   ├── FC-CORS.xml
│   │       │   ├── AM-RemoveAuthHeader.xml
│   │       │   └── RF-*.xml (fault rules)
│   │       ├── resources/jsc/
│   │       │   └── threat-protection.js
│   │       └── petstore-api.xml
│   └── weather-api/
│       ├── pom.xml
│       └── apiproxy/
├── sharedflows/
│   ├── sf-cors/
│   │   ├── pom.xml                    # Child POM (parent → ../../pom.xml)
│   │   └── sharedflowbundle/
│   │       ├── policies/
│   │       └── sharedflows/default.xml
│   ├── sf-logging/
│   │   ├── pom.xml
│   │   └── sharedflowbundle/
│   └── sf-security/
│       ├── pom.xml
│       └── sharedflowbundle/
├── config/
│   └── defaults.yaml                  # Master config for scaffold scripts
├── scripts/
│   ├── create_structure.py            # Creates folder skeleton
│   ├── generate_proxy.py              # Generates proxy XML files
│   ├── generate_sharedflow.py         # Generates shared flow XML files
│   ├── generate_config.py             # Generates edge.json
│   ├── generate_pom.py                # Generates pom.xml files
│   └── scaffold_all.py               # Runs all scripts in order
├── edge.json                          # API products, developers, apps config
├── pom.xml                            # Root POM with Maven plugin config
└── README.md
```

---

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Python | 3.9+ | Scaffold scripts |
| Java | 11 | Maven plugin execution |
| Maven | 3.8+ | Build and deploy |
| Node.js | 20+ | apigeelint |
| gcloud CLI | latest | GCP authentication |
| apigeelint | latest | XML validation |

### Install apigeelint

```bash
npm install -g apigeelint
```

---

## GCP Setup

### 1. Service Account

```bash
export PROJECT_ID=$(gcloud config get-value project)

# Create service account
gcloud iam service-accounts create apigee-github-deployer \
  --display-name="Apigee GitHub Deployer" \
  --project=$PROJECT_ID

# Grant Apigee admin role
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:apigee-github-deployer@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/apigee.admin"
```

### 2. Workload Identity Federation (WIF)

```bash
# Create WIF pool
gcloud iam workload-identity-pools create "github-pool" \
  --location="global" \
  --display-name="GitHub Actions Pool" \
  --project=$PROJECT_ID

# Create OIDC provider
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --display-name="GitHub Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --project=$PROJECT_ID

# Allow GitHub repo to impersonate the SA
gcloud iam service-accounts add-iam-policy-binding \
  "apigee-github-deployer@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')/locations/global/workloadIdentityPools/github-pool/attribute.repository/YOUR_GITHUB_ORG/YOUR_REPO" \
  --project=$PROJECT_ID
```

### 3. Attach Service Account to Apigee Environment

```bash
curl -X PATCH \
  "https://apigee.googleapis.com/v1/organizations/$PROJECT_ID/environments/eval" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  -d "{\"serviceAccount\": \"apigee-github-deployer@${PROJECT_ID}.iam.gserviceaccount.com\"}"
```

### 4. GitHub Secrets

Add these in **GitHub → Settings → Secrets and variables → Actions**:

| Secret | Value |
|--------|-------|
| `WORKLOAD_IDENTITY_PROVIDER` | `projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider` |
| `SERVICE_ACCOUNT_EMAIL` | `apigee-github-deployer@PROJECT_ID.iam.gserviceaccount.com` |
| `APIGEE_ORG` | Your GCP project ID |
| `APIGEE_ENV` | `eval` |

---

## Scaffolding

### Generate everything from defaults.yaml

```bash
python scripts/scaffold_all.py
```

### Generate individual artifacts

```bash
# Create folder structure only
python scripts/create_structure.py

# Generate proxy XMLs
python scripts/generate_proxy.py

# Generate shared flow XMLs
python scripts/generate_sharedflow.py

# Generate edge.json (products, developers, apps)
python scripts/generate_config.py

# Generate pom.xml files
python scripts/generate_pom.py
```

### Regenerate (overwrite existing)

```bash
python scripts/scaffold_all.py --force
python scripts/generate_proxy.py --force
```

---

## Configuration

### defaults.yaml

Master configuration file at `config/defaults.yaml` that drives all scaffold scripts:

```yaml
proxies:
  - name: petstore-api
    basepath: /petstore/v1
    target_url: https://petstore3.swagger.io
    quota: 100
    quota_interval: 1
    quota_unit: minute
    spike_arrest_rate: 30ps
    auth_type: apikey        # apikey or oauth
    cors: true
    threat_protection: true
    fault_rules:
      - name: InvalidKey
        condition: "fault.name = 'InvalidApiKey'"
        message: "Invalid API Key"
        status: 401

sharedflows:
  - name: sf-cors
    type: cors-preflight
  - name: sf-logging
    type: message-logging
  - name: sf-security
    type: verify-api-key

products:
  - name: petstore-product
    proxies: [petstore-api]
    quota: "100"
    quota_interval: "1"
    quota_unit: minute
    scopes: [read, write]

developers:
  - email: dev@example.com
    firstName: Dev
    lastName: User

apps:
  - name: petstore-app
    developer: dev@example.com
    products: [petstore-product]
```

### edge.json

Consumed by `apigee-config-maven-plugin` for deploying products, developers, and apps:

```json
{
  "orgConfig": {
    "apiProducts": [...],
    "developers": [...],
    "developerApps": {
      "dev@example.com": [...]
    }
  }
}
```

---

## Linting

### Lint all proxies

```bash
for dir in apiproxies/*/apiproxy; do
  NAME=$(basename $(dirname "$dir"))
  echo "=== $NAME ==="
  apigeelint -s "$dir" -f table.js --profile apigee
done
```

### Lint all shared flows

```bash
for dir in sharedflows/*/sharedflowbundle; do
  NAME=$(basename $(dirname "$dir"))
  echo "=== $NAME ==="
  apigeelint -s "$dir" -f table.js --profile apigee
done
```

### Lint a single proxy

```bash
apigeelint -s apiproxies/petstore-api/apiproxy -f table.js --profile apigee
```

### Common lint errors

| Rule | Issue | Fix |
|------|-------|-----|
| BN011 | Whitespace before `<?xml` | Remove leading spaces/newlines — byte 0 must be `<` |
| PD003 | Unconditional RouteRule before conditional | Move conditional RouteRule above unconditional |
| PD005 | VirtualHost in Apigee X | Remove `<VirtualHost>` element |
| BN010 | Missing referenced policy file | Ensure all policies in ProxyEndpoint have matching XML files |

---

## Deployment

### Deployment order (critical)

```
1. Shared Flows  →  2. API Proxies  →  3. Config (Products → Developers → Apps)
```

Shared flows must deploy first because proxies reference them via FlowCallout policies.

### Manual deployment (local)

```bash
TOKEN=$(gcloud auth print-access-token)

# Deploy a shared flow
cd sharedflows/sf-cors
mvn clean install -Peval \
  -Dorg="$PROJECT_ID" -Denv="eval" -Dbearer="$TOKEN" \
  -Dapigee.apitype=sharedflow

# Deploy a proxy
cd apiproxies/petstore-api
mvn clean install -Peval \
  -Dorg="$PROJECT_ID" -Denv="eval" -Dbearer="$TOKEN"

# Deploy config (products, developers, apps)
cd ../..  # repo root
mvn install -Pconfig-deploy \
  -Dapigee.org="$PROJECT_ID" -Dapigee.env="eval" \
  -Dapigee.hosturl=https://apigee.googleapis.com \
  -Dapigee.apiversion=v1 -Dapigee.bearer="$TOKEN" \
  -Dapigee.config.options=update -Dapigee.config.file=edge.json
```

---

## GitHub Actions Workflows

### deploy-sharedflows.yaml

- **Trigger:** `push` to `sharedflows/**` or `pom.xml` on `main`, plus `workflow_dispatch`
- **Jobs:** detect → lint → maven-deploy (matrix per shared flow)
- **Maven:** `-Peval -Dapigee.apitype=sharedflow`

### deploy-proxies.yaml

- **Trigger:** `push` to `apiproxies/**` or `pom.xml` on `main`, plus `workflow_dispatch`
- **Jobs:** detect → lint → maven-deploy (matrix per proxy)
- **Maven:** `-Peval`

### deploy-config.yaml

- **Trigger:** `push` to `edge.json` on `main`, plus `workflow_dispatch`
- **Jobs:** single deploy job
- **Maven:** `-Pconfig-deploy -Dapigee.config.file=edge.json`

### ci-lint.yaml

- **Trigger:** pull requests
- **Jobs:** lint all proxies and shared flows
- **Tool:** `apigeelint --profile apigee --maxWarnings 10`

### Change detection

All deploy workflows use **git diff-based change detection**:
- On `push`: only deploys artifacts with file changes
- On `workflow_dispatch`: deploys **all** artifacts
- On first push (zero SHA): deploys all artifacts

---

## Maven POM Structure

### Root POM (`pom.xml`)

Contains two profiles:

| Profile | Purpose | Plugins |
|---------|---------|---------|
| `eval` | Deploy proxies and shared flows | `maven-resources-plugin:3.3.1`, `apigee-edge-maven-plugin:2.5.2` |
| `config-deploy` | Deploy products, developers, apps | `apigee-config-maven-plugin:2.7.0` |

Key properties (passed via `-D` flags):

| Property | Flag | Description |
|----------|------|-------------|
| `org` | `-Dorg` | GCP project ID (Apigee org) |
| `env` | `-Denv` | Apigee environment (`eval`) |
| `bearer` | `-Dbearer` | OAuth2 access token |

Plugin repositories (at project level):
- Maven Central
- `https://apigee.github.io/apigee-config-maven-plugin/maven/repo`
- `https://apigee.github.io/apigee-edge-maven-plugin/maven/repo`

### Child POM (per artifact)

Minimal — just references the root POM as parent:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
    <modelVersion>4.0.0</modelVersion>
    <parent>
        <groupId>apigee</groupId>
        <artifactId>apigee-proxy-parent</artifactId>
        <version>1.0.0</version>
        <relativePath>../../pom.xml</relativePath>
    </parent>
    <artifactId>petstore-api</artifactId>
    <packaging>pom</packaging>
    <name>petstore-api</name>
</project>
```

---

## Adding New Proxies or Shared Flows

### Option 1 — Re-scaffold (new artifacts)

1. Add the new proxy/shared flow to `config/defaults.yaml`
2. Run `python scripts/scaffold_all.py` (skips existing, creates new)
3. Run `apigeelint` to validate
4. Push to `main` — workflow auto-deploys

### Option 2 — Manual

1. Copy an existing proxy/shared flow directory
2. Update XML files (name, basepath, target URL, policies)
3. Create `pom.xml` with parent reference
4. Lint and push

---

## Updating Existing Artifacts

| Change | Approach |
|--------|----------|
| Add/remove a policy | Edit proxy XML files directly, push |
| Change target URL | Edit `targets/default.xml`, push |
| Change quota/rate limit | Edit policy XML, push |
| Add a new resource path | Edit `proxies/default.xml`, add Flow |
| Update API product | Edit `edge.json`, push |
| Re-scaffold from scratch | Run with `--force` flag |

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `fromJson: empty input` | Detect job output empty matrix | Add empty guard and `has_changes` output |
| `MISSING_SERVICE_ACCOUNT` | No SA attached to Apigee environment | Attach SA via API or console |
| `apigee-config-maven-plugin not found` | Wrong version or missing plugin repos | Use version `2.7.0`, ensure `pluginRepositories` at project level |
| `delay: Cannot find field` | `apigee.delay` not supported in Apigee X | Remove `apigee.delay` and `apigee.override.delay` from POM |
| `403 Permission Denied` | SA missing required IAM roles | Grant `roles/apigee.admin` to the SA |
| `BN011 XML not well-formed` | Whitespace before `<?xml` declaration | Remove leading whitespace — first byte must be `<` |
| Workflow not triggered | Changed file not in trigger paths | Add `workflow_dispatch` and workflow path to triggers |
