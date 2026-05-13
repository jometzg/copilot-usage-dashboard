variable "prefix" {
  description = "Short prefix applied to all resource names. Use lowercase letters and hyphens only."
  type        = string
  default     = "copilot-dash"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "uksouth"
}

variable "resource_group_name" {
  description = "Name of the resource group to create."
  type        = string
  default     = "copilot-dashboard-rg"
}

variable "image_repository" {
  description = "Container image repository name in ACR."
  type        = string
  default     = "otel-collector"
}

variable "image_tag" {
  description = "Container image tag to deploy. Use immutable tags in CI/CD (for example, git SHA)."
  type        = string
  default     = "latest"
}
