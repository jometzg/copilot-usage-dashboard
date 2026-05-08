variable "prefix" {
  description = "Short prefix applied to all resource names. Use lowercase letters and hyphens only."
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
