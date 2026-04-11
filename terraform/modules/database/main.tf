resource "azurerm_mssql_server" "main" {
  name                         = "sql-${var.name_prefix}"
  resource_group_name          = var.resource_group_name
  location                     = var.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_login
  administrator_login_password = var.sql_admin_password
  minimum_tls_version          = "1.2"
  tags                         = var.tags

  # No public internet access — all connections must come through the private endpoint
  public_network_access_enabled = false

  azuread_administrator {
    login_username = var.aad_admin_login
    object_id      = var.aad_admin_object_id
    # false = both SQL auth and AAD auth allowed (safer for initial setup)
    # Set to true once Managed Identity auth is confirmed working
    azuread_authentication_only = false
  }
}

resource "azurerm_mssql_database" "main" {
  name         = "sqldb-${var.name_prefix}"
  server_id    = azurerm_mssql_server.main.id
  collation = "SQL_Latin1_General_CP1_CI_AS"
  sku_name  = "GP_S_Gen5_1"  # Serverless: auto-scales 0.5–4 vCores, auto-pauses when idle
  # license_type removed — not supported by Serverless SKU (provider enforces at plan time)
  max_size_gb  = 32
  tags         = var.tags

  auto_pause_delay_in_minutes = 60  # Pause after 60 min idle to save cost
  min_capacity                = 0.5
}

# Microsoft Defender for SQL — detects SQL injection, anomalous access patterns, brute force
resource "azurerm_mssql_server_security_alert_policy" "main" {
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mssql_server.main.name
  state               = "Enabled"

  # CKV_AZURE_26 + CKV_AZURE_27: send alerts to the ops email address AND account admins
  email_addresses         = [var.alert_email]
  email_account_admins    = true
  retention_days          = 90
}

# CKV_AZURE_23 + CKV_AZURE_24: enable auditing with 90-day retention sent to Log Analytics
resource "azurerm_mssql_server_extended_auditing_policy" "main" {
  server_id              = azurerm_mssql_server.main.id
  log_monitoring_enabled = true
  retention_in_days      = 90
}

# Private Endpoint — gives SQL Server a private IP inside snet-data
resource "azurerm_private_endpoint" "sql" {
  name                = "pe-sql-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.data_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-sql-${var.name_prefix}"
    private_connection_resource_id = azurerm_mssql_server.main.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-group-sql"
    private_dns_zone_ids = [var.sql_dns_zone_id]
  }
}
