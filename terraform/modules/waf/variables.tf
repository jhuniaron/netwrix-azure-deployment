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

variable "tags" {
  type    = map(string)
  default = {}
}
