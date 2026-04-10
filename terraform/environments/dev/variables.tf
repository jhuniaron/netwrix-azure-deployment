variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "project" {
  description = "Short project name used in all resource names"
  type        = string
  default     = "netwrix"
}

variable "environment" {
  description = "Deployment environment (dev / prod)"
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "australiaeast"
}

variable "app_service_sku" {
  description = "App Service Plan SKU"
  type        = string
  default     = "P1v3"
}

variable "sql_admin_login" {
  description = "SQL Server administrator login name"
  type        = string
  sensitive   = true
}

variable "sql_admin_password" {
  description = "SQL Server administrator password"
  type        = string
  sensitive   = true
}

variable "aad_admin_login" {
  description = "Azure AD user/group display name to be SQL AAD admin"
  type        = string
}

variable "aad_admin_object_id" {
  description = "Azure AD object ID of the SQL AAD admin"
  type        = string
}

variable "alert_email" {
  description = "Email address for monitoring alerts"
  type        = string
}

variable "ssl_cert_keyvault_secret_id" {
  description = "Key Vault secret ID for the SSL certificate. Leave empty to use App Gateway's self-signed cert for dev."
  type        = string
  default     = ""
}
