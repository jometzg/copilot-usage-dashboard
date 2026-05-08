# GitHub Copilot Usage Dashboard

Visualise GitHub Copilot usage across your organisation using OpenTelemetry, Azure Application Insights, and Azure Managed Grafana.

![Sample dashboard](sample-dashboard.png)

VS Code sends Copilot telemetry (chat sessions, agent invocations, token usage, geographic data) via OTLP to a self-hosted OTel Collector running on Azure Container Apps. The collector forwards the data to Application Insights, where it is queried by a Grafana dashboard.

## Architecture

```
VS Code (GitHub Copilot)
        │  OTLP/HTTP (port 4318)
        ▼
OTel Collector  (Azure Container Apps — public HTTPS endpoint)
        │  Azure Monitor exporter
        ▼
Application Insights (workspace-based)
        │  Azure Monitor data source
        ▼
Azure Managed Grafana
```

## Repository Contents

| File / Folder | Purpose |
|---|---|
| `Dockerfile` | Builds the custom OTel Collector image from `otel/opentelemetry-collector-contrib` |
| `config.yaml` | OTel Collector pipeline config (receivers, processors, Azure Monitor exporter) |
| `grafana-agent-usage-geo.json` | Grafana dashboard JSON — import this into your Managed Grafana instance |
| `KQL-queries.txt` | Sample KQL queries for exploring raw data in Application Insights |
| `terraform/` | Terraform code to provision all required Azure infrastructure |
| `plan.md` | Detailed step-by-step build guide |

## Quick Start

### 1. Prerequisites

- Azure subscription with **Contributor** rights
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) — `az login`
- [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.5
- [Docker](https://docs.docker.com/get-docker/)
- VS Code with a **GitHub Copilot Business or Enterprise** licence

### 2. Provision Azure infrastructure

```bash
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

This creates: a resource group, Log Analytics workspace, Application Insights, Container Registry, Container App Environment, OTel Collector Container App (public HTTPS), and Azure Managed Grafana — with all required role assignments.

### 3. Build and push the collector image

```bash
ACR=$(terraform -chdir=terraform output -raw acr_login_server)
az acr login --name "${ACR%%.*}"
docker build -t ${ACR}/otel-collector:latest .
docker push ${ACR}/otel-collector:latest

# Trigger a new Container App revision to pull the image
az containerapp update \
  --name copilot-dash-collector \
  --resource-group copilot-dashboard-rg \
  --image ${ACR}/otel-collector:latest
```

### 4. Configure VS Code

Add the following to your VS Code **User Settings** (`settings.json`), replacing `<fqdn>` with the output of `terraform -chdir=terraform output -raw container_app_fqdn`:

```json
{
  "github.copilot.nextEditSuggestions.enabled": true,
  "github.copilot.chat.otel.enabled": true,
  "github.copilot.chat.otel.exporterType": "otlp-http",
  "github.copilot.chat.otel.otlpEndpoint": "https://<fqdn>"
}
```

Restart VS Code. Telemetry will begin flowing as soon as you use Copilot Chat.

### 5. Import the Grafana dashboard

1. Open the Managed Grafana instance (`terraform -chdir=terraform output -raw grafana_endpoint`)
2. **Connections → Data sources → Add** → **Azure Monitor** → Authentication: **Managed Identity** → **Save & Test**
3. **Dashboards → Import → Upload JSON file** → select `grafana-agent-usage-geo.json`
4. Map the `DS_AZURE_MONITOR` input to the data source just created → **Import**

## Terraform Variables

Override defaults by creating `terraform/terraform.tfvars`:

```hcl
prefix              = "copilot-dash"   # prefix for all resource names
location            = "northeurope"    # Azure region
resource_group_name = "copilot-dashboard-rg"
```

## Tear Down

```bash
terraform -chdir=terraform destroy
```

## Detailed Guide

See [plan.md](plan.md) for a full walkthrough including Terraform resource descriptions, verification steps, and security notes.
