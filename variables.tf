variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
}

variable "storage_account_name" {
  description = "Name of the Azure Storage Account"
  type        = string
}

variable "function_local_path" {
  description = "path yo local function"
  type        = string
}

variable "service_plan_name" {
  description = "Name of the Azure Service Plan"
  type        = string
}

variable "azurerm_linux_function_app" {
  description = "Name of the Azure Function App"
  type        = string
}

variable "key_vault_name" {
  description = "Name of the Azure Key Vault"
  type        = string
}

variable "service_bus_name" {
  description = "Name of the Service Bus"
  type        = string
}

variable "service_bus_queue" {
  description = "Name of the Service Bus Queue"
  type        = string
}

variable "secrets" {
  description = "A map of secrets where keys are secret names and values are secret values."
  type        = map(string)
}
