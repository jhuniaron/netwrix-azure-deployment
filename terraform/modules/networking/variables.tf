variable "name_prefix" {
  description = "Prefix used in all resource names"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group to create"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "vnet_cidr" {
  description = "CIDR block for the Virtual Network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "gateway_subnet_cidr" {
  description = "CIDR for the Application Gateway subnet"
  type        = string
  default     = "10.0.0.0/26"
}

variable "app_subnet_cidr" {
  description = "CIDR for the App Service VNet Integration subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "data_subnet_cidr" {
  description = "CIDR for the SQL Private Endpoint subnet"
  type        = string
  default     = "10.0.2.0/28"
}

variable "pe_subnet_cidr" {
  description = "CIDR for the Key Vault Private Endpoint subnet"
  type        = string
  default     = "10.0.3.0/28"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
