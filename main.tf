terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "3.88.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
       prevent_deletion_if_contains_resources = false
     }
  }
}

resource "azurerm_resource_group" "linux-function-rg" {
  name     = var.resource_group_name
  location = "East US"
}

resource "azurerm_storage_account" "linux-storage-account" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.linux-function-rg.name
  location                 = azurerm_resource_group.linux-function-rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "linux_storage_container" {
  name                 = "function-releases"
  storage_account_name = azurerm_storage_account.linux-storage-account.name
}

resource "azurerm_role_assignment" "linux_app_storage_access" {
  scope                = azurerm_storage_account.linux-storage-account.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.linux-python-linux-function-app.identity[0].principal_id
}

resource "azurerm_service_plan" "linux-service-plan" {
  name                = var.service_plan_name
  resource_group_name = azurerm_resource_group.linux-function-rg.name
  location            = azurerm_resource_group.linux-function-rg.location
  os_type             = "Linux"
  sku_name            = "Y1"
}

resource "azurerm_application_insights" "linux-application-insights" {
  name                = "application-insights-${var.azurerm_linux_function_app}"
  location            = "${azurerm_resource_group.linux-function-rg.location}"
  resource_group_name = "${azurerm_resource_group.linux-function-rg.name}"
  application_type    = "other"
}

# data "archive_file" "function_zip" {
#   type        = "zip"
#   output_path = "function.zip"

#   source_dir = "../../azure_function/"
# }

data "archive_file" "function" {
  type        = "zip"
  source_dir  = var.function_local_path
  output_path = "${path.module}/functions.zip"

  depends_on = [null_resource.pip]
}

resource "azurerm_storage_blob" "linux_storage_blob_function" {
  name                   = "functions-${substr(data.archive_file.function.output_md5, 0, 6)}.zip"
  storage_account_name   = azurerm_storage_account.linux-storage-account.name
  storage_container_name = azurerm_storage_container.linux_storage_container.name
  type                   = "Block"
  content_md5            = data.archive_file.function.output_md5
  source                 = "${path.module}/functions.zip"
}

# resource "azurerm_servicebus_namespace" "linux_servicebus_function" {
#   name                = var.service_bus_name
#   location            = azurerm_resource_group.linux-function-rg.location
#   resource_group_name = azurerm_resource_group.linux-function-rg.name
#   sku                 = "Basic"
# }

# resource "azurerm_servicebus_queue" "linux_servicebus_queue" {
#   name                = var.service_bus_queue
#   namespace_id      = azurerm_servicebus_namespace.linux_servicebus_function.id
# }

# resource "azurerm_role_assignment" "linux_servicebus_send_permission" {
#   scope                = azurerm_servicebus_namespace.linux_servicebus_function.id
#   role_definition_name = "Azure Service Bus Data Sender"
#   principal_id         = azurerm_linux_function_app.linux-python-linux-function-app.identity[0].principal_id
# }

resource "null_resource" "pip" {
  triggers = {
    requirements_md5 = "${filemd5("../../azure_function/requirements.txt")}"
  }
  provisioner "local-exec" {    
    command = "pip install --target='.python_packages/lib/site-packages' -r requirements.txt"
    working_dir = var.function_local_path
  }
}

resource "azurerm_linux_function_app" "linux-python-linux-function-app" {
  name                = var.azurerm_linux_function_app
  resource_group_name = azurerm_resource_group.linux-function-rg.name
  location            = azurerm_resource_group.linux-function-rg.location
  # zip_deploy_file     = var.function_local_path
  
  service_plan_id            = azurerm_service_plan.linux-service-plan.id
  storage_account_name       = azurerm_storage_account.linux-storage-account.name
  storage_account_access_key = azurerm_storage_account.linux-storage-account.primary_access_key
  https_only                 = true
  site_config {
    application_insights_key = azurerm_application_insights.linux-application-insights.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.linux-application-insights.connection_string
    cors {
      allowed_origins     = ["https://gitlab.com","https://portal.azure.com"]
      support_credentials = true
    }
    application_stack {
        python_version = 3.11 #FUNCTIONS_WORKER_RUNTIME        
  }
  }
  app_settings = {
    "APPINSIGHTS_INSTRUMENTATIONKEY" = "${azurerm_application_insights.linux-application-insights.instrumentation_key}"
    "WEBSITE_RUN_FROM_PACKAGE" = azurerm_storage_blob.linux_storage_blob_function.url
  }
  identity {
    type = "SystemAssigned"
  }
}



data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "linux-key-vault" {
  name                = var.key_vault_name
  resource_group_name = azurerm_resource_group.linux-function-rg.name
  location            = azurerm_resource_group.linux-function-rg.location
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  sku_name = "standard"

}

resource "azurerm_key_vault_access_policy" "linux-user-key-vault-access-policy" {
    depends_on = [ azurerm_key_vault.linux-key-vault]
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id
    key_vault_id = azurerm_key_vault.linux-key-vault.id

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
      "Purge"
    ]
    
}

resource "azurerm_key_vault_access_policy" "linux-app-key-vault-access-policy" {
  depends_on = [ azurerm_key_vault.linux-key-vault]
  key_vault_id = azurerm_key_vault.linux-key-vault.id
  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = azurerm_linux_function_app.linux-python-linux-function-app.identity[0].principal_id
  
  secret_permissions = [
    "Get",
    "List",
  ]

}

resource "azurerm_key_vault_secret" "linux-key-vault-key" {
  depends_on = [ azurerm_key_vault_access_policy.linux-user-key-vault-access-policy, azurerm_key_vault_access_policy.linux-app-key-vault-access-policy ]
  for_each     = var.secrets
  name         = each.key
  value        = each.value
  key_vault_id = azurerm_key_vault.linux-key-vault.id
}

resource "azurerm_resource_group_template_deployment" "example" {
  name                = "amirtestlogicapp-template"
  resource_group_name = azurerm_resource_group.linux-function-rg.name

  template_content = file("${path.module}/logic-app-template.json")

  parameters_content = jsonencode({
    "sites_amir_test_python_function_externalid" = {value = azurerm_linux_function_app.linux-python-linux-function-app.id},
    "workflows_amirtestlogicapp_name" = { value = "amirtestlogicapp"}
  })

  deployment_mode = "Incremental"
}


output "arm_example_output" {
  value = jsondecode(azurerm_resource_group_template_deployment.example.output_content)
}

output "resource_group_id" {
  value = azurerm_resource_group.linux-function-rg.id
}

output "storage_account_id" {
  value = azurerm_storage_account.linux-storage-account.id
}

output "service_plan_id" {
  value = azurerm_service_plan.linux-service-plan.id
}

output "linux_function_app_id" {
  value = azurerm_linux_function_app.linux-python-linux-function-app.id
}

output "key_vault_id" {
  value = azurerm_key_vault.linux-key-vault.id
}
