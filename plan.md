# GitHub Copilot Usage Dashboard — Build from Scratch

This document walks through every step required to build and operate the GitHub Copilot usage dashboard from scratch. The dashboard collects OpenTelemetry telemetry from VS Code, routes it through an OTel Collector hosted on Azure Container Apps into Application Insights, and visualises it in Azure Managed Grafana.

## Architecture

```
VS Code (GitHub Copilot)
        │  OTLP/HTTP (port 4318)
        ▼
OTel Collector  ◄── custom Docker image hosted in Azure Container Registry
(Azure Container Apps — public endpoint)
        │  Azure Monitor exporter
        ▼
Application Insights (workspace-based)
        │  Azure Monitor data source
        ▼
Azure Managed Grafana
```

## Prerequisites

- Azure subscription with **Contributor** rights
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) installed and authenticated (`az login`)
- [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.5
- [Docker](https://docs.docker.com/get-docker/) and Docker CLI
- VS Code with **GitHub Copilot Business or Enterprise** licence
- Git

---

## Step 1 — Parameterise `config.yaml`

Before building the Docker image, replace the hardcoded Application Insights connection string in `config.yaml` with an environment-variable reference. The `otel/opentelemetry-collector-contrib` image natively substitutes `${ENV_VAR}` syntax at startup.

Edit `config.yaml` — change the `azuremonitor` exporter block to:

```yaml
exporters:
  azuremonitor:
    connection_string: "${APPLICATIONINSIGHTS_CONNECTION_STRING}"
```

This keeps the secret out of the image and lets the Container App inject the real value at runtime.

---

## Step 2 — Provision Infrastructure with Terraform

Create a `terraform/` directory and add the following files.

### `terraform/main.tf`

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
  required_version = ">= 1.5"
}

provider "azurerm" {
  features {}
}

# Used by Key Vault tenant_id, KV role assignments, and Grafana Admin role
data "azurerm_client_config" "current" {}

# ── Resource Group ────────────────────────────────────────────────────────────

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# ── Log Analytics Workspace (required for workspace-based App Insights) ───────

resource "azurerm_log_analytics_workspace" "law" {
  name                = "${var.prefix}-law"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# ── Application Insights ──────────────────────────────────────────────────────

resource "azurerm_application_insights" "ai" {
  name                = "${var.prefix}-ai"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  workspace_id        = azurerm_log_analytics_workspace.law.id
  application_type    = "web"
}

# ── Key Vault (stores App Insights connection string) ────────────────────────

resource "azurerm_key_vault" "kv" {
  name                       = "${var.prefix}-kv"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
}

resource "azurerm_key_vault_secret" "ai_conn_str" {
  name         = "AppInsightsConnectionString"
  value        = azurerm_application_insights.ai.connection_string
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_role_assignment.kv_admin_deployer]
}

# Allow the deploying user to manage secrets during provisioning
resource "azurerm_role_assignment" "kv_admin_deployer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ── Container Registry ────────────────────────────────────────────────────────

resource "azurerm_container_registry" "acr" {
  name                = "${replace(var.prefix, "-", "")}acr"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
  admin_enabled       = false

  identity {
    type = "SystemAssigned"
  }
}

# ── Container App Environment ─────────────────────────────────────────────────

resource "azurerm_container_app_environment" "env" {
  name                       = "${var.prefix}-cae"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
}

# ── Container App (OTel Collector) ────────────────────────────────────────────

resource "azurerm_container_app" "collector" {
  name                         = "${var.prefix}-collector"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"

  identity {
    type = "SystemAssigned"
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = "system"
  }

  template {
    container {
      name   = "otel-collector"
      image  = "${azurerm_container_registry.acr.login_server}/otel-collector:latest"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name        = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        secret_name = "appinsights-conn-str"
      }
    }
  }

  secret {
    name                = "appinsights-conn-str"
    key_vault_secret_id = azurerm_key_vault_secret.ai_conn_str.versionless_id
    identity            = "System"
  }

  ingress {
    external_enabled = true
    # OTLP/HTTP on port 4318 — matches github.copilot.chat.otel.exporterType = "otlp-http"
    # For gRPC clients (port 4317) change transport to "http2" and target_port to 4317
    transport = "http"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }

    target_port = 4318
  }
}

# ── AcrPull role — Container App managed identity → ACR ──────────────────────

resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_container_app.collector.identity[0].principal_id
}

# ── Key Vault Secrets User — Container App managed identity → Key Vault ───────

resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_container_app.collector.identity[0].principal_id
}

# ── Azure Managed Grafana ─────────────────────────────────────────────────────

resource "azurerm_dashboard_grafana" "grafana" {
  name                          = "${var.prefix}-grafana"
  location                      = azurerm_resource_group.rg.location
  resource_group_name           = azurerm_resource_group.rg.name
  sku                           = "Standard"
  grafana_major_version         = 10
  zone_redundancy_enabled       = false
  public_network_access_enabled = true
  api_key_enabled               = true

  azure_monitor_workspace_integrations = []

  identity {
    type = "SystemAssigned"
  }
}

# ── Monitoring Reader — Grafana managed identity → resource group ─────────────

resource "azurerm_role_assignment" "grafana_monitoring_reader" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_dashboard_grafana.grafana.identity[0].principal_id
}

# ── Grafana Admin — grant the deploying user access to the Grafana UI ─────────

resource "azurerm_role_assignment" "grafana_admin" {
  scope                = azurerm_dashboard_grafana.grafana.id
  role_definition_name = "Grafana Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}
```

### `terraform/variables.tf`

```hcl
variable "prefix" {
  description = "Short prefix applied to all resource names (lowercase, hyphens OK)."
  type        = string
  default     = "copilot-dash"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "northeurope"
}

variable "resource_group_name" {
  description = "Name of the resource group to create."
  type        = string
  default     = "copilot-dashboard-rg"
}
```

### `terraform/outputs.tf`

```hcl
output "acr_login_server" {
  description = "Container Registry login server hostname."
  value       = azurerm_container_registry.acr.login_server
}

output "container_app_fqdn" {
  description = "Public FQDN of the OTel Collector Container App."
  value       = azurerm_container_app.collector.latest_revision_fqdn
}

output "app_insights_connection_string" {
  description = "Application Insights connection string (keep secret)."
  value       = azurerm_application_insights.ai.connection_string
  sensitive   = true
}

output "grafana_endpoint" {
  description = "Azure Managed Grafana endpoint URL."
  value       = azurerm_dashboard_grafana.grafana.endpoint
}
```

### Run Terraform

```bash
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Note the outputs — you will need `acr_login_server`, `container_app_fqdn`, and `grafana_endpoint` in later steps.

---

## Step 3 — Build and Push the Docker Image

With `config.yaml` already updated (Step 1) and the ACR provisioned (Step 2):

```bash
# Log in to the registry
ACR=$(terraform -chdir=terraform output -raw acr_login_server)
az acr login --name "${ACR%%.*}"

# Build and tag
docker build -t ${ACR}/otel-collector:latest .

# Push
docker push ${ACR}/otel-collector:latest
```

After pushing, trigger a new Container App revision so it pulls the updated image:

```bash
az containerapp update \
  --name copilot-dash-collector \
  --resource-group copilot-dashboard-rg \
  --image ${ACR}/otel-collector:latest
```

---

## Step 4 — Configure VS Code

Each developer who should contribute telemetry adds the following to their VS Code **User Settings** (`settings.json`):

```json
{
  "github.copilot.nextEditSuggestions.enabled": true,
  "github.copilot.chat.otel.enabled": true,
  "github.copilot.chat.otel.exporterType": "otlp-http",
  "github.copilot.chat.otel.otlpEndpoint": "https://<container_app_fqdn>"
}
```

Replace `<container_app_fqdn>` with the value from:

```bash
terraform -chdir=terraform output -raw container_app_fqdn
```

**Steps in VS Code:**

1. Open the Command Palette (`Ctrl+Shift+P` / `Cmd+Shift+P`) → **Preferences: Open User Settings (JSON)**
2. Add the four settings above with your collector FQDN
3. Save and **restart VS Code**
4. Use GitHub Copilot Chat — telemetry will begin flowing to the collector within seconds

---

## Step 5 — Set Up Azure Managed Grafana

### 5.1 Open the Grafana instance

Navigate to the Managed Grafana resource in the Azure Portal and click **Visit** to open the Grafana UI. Sign in with your Entra ID account (the Terraform `grafana_admin` role assignment grants access to the user who ran `terraform apply`).

### 5.2 Add the Azure Monitor data source

1. In Grafana, go to **Connections → Data sources → Add new data source**
2. Select **Azure Monitor**
3. Set **Authentication** to **Managed Identity**
4. Set **Default subscription** to your Azure subscription
5. Set **Default resource group** to `copilot-dashboard-rg` (or as configured in `var.resource_group_name`)
6. Click **Save & Test** — it should report a successful connection

> The Grafana system-assigned managed identity was granted **Monitoring Reader** on the resource group by Terraform, so no additional credentials are needed.

### 5.3 Import the dashboard

1. In Grafana, go to **Dashboards → Import**
2. Click **Upload dashboard JSON file**
3. Select `grafana-agent-usage-geo.json` from this repository
4. On the next screen, map the `DS_AZURE_MONITOR` data source input to the Azure Monitor data source you created in 5.2
5. Click **Import**

The dashboard includes panels for agent invocations, token usage, geographic distribution of users, dependency traces, error rates, and session timelines.

### 5.4 Additional KQL panels

The file `KQL-queries.txt` contains useful KQL queries targeting the Application Insights `dependencies` table. To use them in a custom panel:

1. Edit or add a panel in Grafana
2. Set data source to **Azure Monitor**
3. Set service to **Logs**
4. Select your Application Insights resource
5. Paste the query from `KQL-queries.txt`

---

## Step 6 — Verification

| Check | How |
|---|---|
| OTel data reaching collector | Azure Portal → Container App → **Log stream** — look for `POST /v1/traces` and `POST /v1/metrics` entries |
| Data arriving in Application Insights | Application Insights → **Transaction Search** → filter by type `Dependency` |
| Grafana panels populated | Open the imported dashboard — panels should show data after a few minutes of Copilot activity |
| Geo panel shows locations | Run the `countries` query from `KQL-queries.txt` directly in App Insights to confirm geo data is captured |

---

## Security Notes

- The `app_insights_connection_string` Terraform output is marked `sensitive` — never commit it to source control.
- `config.yaml` uses `${APPLICATIONINSIGHTS_CONNECTION_STRING}` substitution; the real value is injected only at Container App runtime via the environment variable set in Terraform.
- The Container Registry uses managed identity pull — no admin credentials or stored passwords.
- Consider restricting Container App ingress to known IP ranges if the collector endpoint should not be publicly writable by anyone on the internet.

---

## Tear Down

```bash
terraform -chdir=terraform destroy
```
