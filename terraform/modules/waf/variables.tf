variable "name_prefix" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "gateway_subnet_id" {
  description = "Subnet ID for the Application Gateway"
  type        = string
}

variable "app_service_hostname" {
  description = "Default hostname of the App Service backend (e.g. app-netwrix-dev.azurewebsites.net)"
  type        = string
}

variable "appgw_identity_id" {
  description = "Resource ID of the user-assigned managed identity for App Gateway (for Key Vault cert access)"
  type        = string
}

variable "appgw_cert_secret_id" {
  description = "Versionless secret ID of the TLS certificate stored in Key Vault"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
