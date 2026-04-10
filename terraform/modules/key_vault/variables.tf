variable "name_prefix" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "pe_subnet_id" {
  description = "Subnet ID for the Key Vault private endpoint"
  type        = string
}

variable "keyvault_dns_zone_id" {
  description = "Private DNS Zone ID for Key Vault"
  type        = string
}

variable "app_service_principal_id" {
  description = "Object ID of the App Service system-assigned managed identity"
  type        = string
}

variable "db_connection_string" {
  description = "Full connection string for the SQL database"
  type        = string
  sensitive   = true
}

variable "appinsights_connection_string" {
  description = "Application Insights connection string"
  type        = string
  sensitive   = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
