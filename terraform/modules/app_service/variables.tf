variable "name_prefix" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "app_subnet_id" {
  description = "Subnet ID for App Service VNet Integration (outbound)"
  type        = string
}

variable "gateway_subnet_id" {
  description = "Resource ID of the Application Gateway subnet — used for VNet-based inbound restriction"
  type        = string
}

variable "gateway_subnet_cidr" {
  description = "CIDR of the Application Gateway subnet — only this is allowed inbound to the app"
  type        = string
}

variable "sku_name" {
  description = "App Service Plan SKU (e.g. P1v3)"
  type        = string
  default     = "P1v3"
}

variable "environment" {
  description = "ASPNETCORE_ENVIRONMENT value"
  type        = string
}

variable "appinsights_secret_uri" {
  description = "Key Vault secret URI for the Application Insights connection string"
  type        = string
}

variable "db_connstring_secret_uri" {
  description = "Key Vault secret URI for the database connection string"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
