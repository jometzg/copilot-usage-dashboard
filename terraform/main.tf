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
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = azurerm_application_insights.ai.connection_string
      }
    }
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

data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "grafana_admin" {
  scope                = azurerm_dashboard_grafana.grafana.id
  role_definition_name = "Grafana Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}
