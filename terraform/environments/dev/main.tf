locals {
  name_prefix = "${var.project}-${var.environment}"
  tags = {
    project     = var.project
    environment = var.environment
    managed_by  = "terraform"
  }
}

# ---------------------------------------------------------------
# 1. NETWORKING — VNet, subnets, NSGs, private DNS zones
# All other modules depend on outputs from this one.
# ---------------------------------------------------------------
module "networking" {
  source              = "../../modules/networking"
  name_prefix         = local.name_prefix
  resource_group_name = "rg-${local.name_prefix}"
  location            = var.location
  vnet_cidr           = "10.0.0.0/16"
  gateway_subnet_cidr = "10.0.0.0/26"
  app_subnet_cidr     = "10.0.1.0/24"
  data_subnet_cidr    = "10.0.2.0/28"
  pe_subnet_cidr      = "10.0.3.0/28"
  tags                = local.tags
}

# ---------------------------------------------------------------
# 2. DATABASE — Azure SQL Server + Database + Private Endpoint
# Created early so the FQDN is available for the connection string.
# ---------------------------------------------------------------
module "database" {
  source              = "../../modules/database"
  name_prefix         = local.name_prefix
  location            = module.networking.location
  resource_group_name = module.networking.resource_group_name
  data_subnet_id      = module.networking.data_subnet_id
  sql_dns_zone_id     = module.networking.sql_dns_zone_id
  sql_admin_login     = var.sql_admin_login
  sql_admin_password  = var.sql_admin_password
  aad_admin_login     = var.aad_admin_login
  aad_admin_object_id = var.aad_admin_object_id
  alert_email         = var.alert_email
  tags                = local.tags
}

# ---------------------------------------------------------------
# 3. APP SERVICE — Linux Web App + autoscale
# Created before Key Vault so we can pass the Managed Identity
# principal_id into the Key Vault module for RBAC assignment.
# ---------------------------------------------------------------
module "app_service" {
  source              = "../../modules/app_service"
  name_prefix         = local.name_prefix
  location            = module.networking.location
  resource_group_name = module.networking.resource_group_name
  app_subnet_id       = module.networking.app_subnet_id
  gateway_subnet_cidr = module.networking.gateway_subnet_cidr
  sku_name            = var.app_service_sku
  environment         = var.environment

  # These reference Key Vault secrets — the URIs are known ahead of time
  # even though the secrets are created in the key_vault module below.
  # Terraform resolves the dependency graph automatically.
  appinsights_secret_uri   = module.key_vault.appinsights_connstring_secret_uri
  db_connstring_secret_uri = module.key_vault.db_connstring_secret_uri
  tags                     = local.tags
}

# ---------------------------------------------------------------
# 4. KEY VAULT — Secrets + RBAC + Private Endpoint
# Needs the App Service principal_id to grant it Secrets User role.
# Needs the DB FQDN and App Insights conn string to store as secrets.
# ---------------------------------------------------------------
module "key_vault" {
  source                        = "../../modules/key_vault"
  name_prefix                   = local.name_prefix
  location                      = module.networking.location
  resource_group_name           = module.networking.resource_group_name
  pe_subnet_id                  = module.networking.pe_subnet_id
  keyvault_dns_zone_id          = module.networking.keyvault_dns_zone_id
  app_service_principal_id      = module.app_service.principal_id
  appinsights_connection_string = module.monitoring.app_insights_connection_string

  # Passwordless connection string — App Service MI authenticates via AAD
  db_connection_string = "Server=tcp:${module.database.sql_server_fqdn},1433;Initial Catalog=${module.database.sql_database_name};Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  tags                 = local.tags
}

# ---------------------------------------------------------------
# 5. WAF — Application Gateway + WAF Policy
# Needs the App Service hostname to route backend traffic.
# ---------------------------------------------------------------
module "waf" {
  source               = "../../modules/waf"
  name_prefix          = local.name_prefix
  location             = module.networking.location
  resource_group_name  = module.networking.resource_group_name
  gateway_subnet_id    = module.networking.gateway_subnet_id
  app_service_hostname = module.app_service.default_hostname
  tags                 = local.tags
}

# ---------------------------------------------------------------
# 6. MONITORING — Log Analytics + App Insights + Alerts
# Created last because it needs both the App Gateway and App Service IDs.
# ---------------------------------------------------------------
module "monitoring" {
  source              = "../../modules/monitoring"
  name_prefix         = local.name_prefix
  location            = module.networking.location
  resource_group_name = module.networking.resource_group_name
  alert_email         = var.alert_email
  appgw_id            = module.waf.appgw_id
  app_service_id      = module.app_service.app_id
  tags                = local.tags
}
