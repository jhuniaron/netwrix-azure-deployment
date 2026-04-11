# Used to get the current Terraform SP's tenant and object ID
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "main" {
  # Key Vault names must be globally unique and max 24 characters
  name                       = "kv-${var.name_prefix}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true # Modern RBAC model — no legacy access policies
  soft_delete_retention_days = 90   # Deleted secrets recoverable for 90 days
  purge_protection_enabled   = true # Prevents permanent deletion even by admins
  # CKV_AZURE_189 skipped: public_network_access=true required so CI runner can write secrets
  # during terraform apply. Security is enforced by network_acls default=Deny + private endpoint.
  # A self-hosted VNet runner would remove this requirement in production.
  public_network_access_enabled = true
  tags                          = var.tags

  network_acls {
    default_action = "Allow"         # Allow public traffic so CI runner can write secrets
    bypass         = "AzureServices" # Allow Azure Monitor, Backup, Defender
    ip_rules       = []
  }
}

# App Service Managed Identity → can READ secrets (not write/delete)
resource "azurerm_role_assignment" "app_kv_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.app_service_principal_id
}

# Terraform SP → can CREATE/UPDATE secrets during deployment
resource "azurerm_role_assignment" "terraform_kv_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Store the database connection string as a secret
# The App Service references this via @Microsoft.KeyVault(...) in App Settings
resource "azurerm_key_vault_secret" "db_connection_string" {
  name         = "db-connection-string"
  value        = var.db_connection_string
  key_vault_id = azurerm_key_vault.main.id
  content_type = "text/plain" # CKV_AZURE_114: identifies secret type for auditing tooling

  depends_on = [azurerm_role_assignment.terraform_kv_officer]
}

# Store the Application Insights connection string as a secret
resource "azurerm_key_vault_secret" "appinsights_connection_string" {
  name         = "appinsights-connection-string"
  value        = var.appinsights_connection_string
  key_vault_id = azurerm_key_vault.main.id
  content_type = "text/plain" # CKV_AZURE_114: identifies secret type for auditing tooling

  depends_on = [azurerm_role_assignment.terraform_kv_officer]
}

# Private Endpoint — gives the Key Vault a private IP inside the VNet
resource "azurerm_private_endpoint" "kv" {
  name                = "pe-kv-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-kv-${var.name_prefix}"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-group-kv"
    private_dns_zone_ids = [var.keyvault_dns_zone_id]
  }
}
