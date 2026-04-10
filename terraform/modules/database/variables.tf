variable "name_prefix" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "data_subnet_id" {
  description = "Subnet ID for the SQL Private Endpoint"
  type        = string
}

variable "sql_dns_zone_id" {
  description = "Private DNS Zone ID for SQL"
  type        = string
}

variable "sql_admin_login" {
  description = "SQL Server administrator login"
  type        = string
  sensitive   = true
}

variable "sql_admin_password" {
  description = "SQL Server administrator password"
  type        = string
  sensitive   = true
}

variable "aad_admin_login" {
  description = "Display name of the Azure AD SQL administrator"
  type        = string
}

variable "aad_admin_object_id" {
  description = "Object ID of the Azure AD SQL administrator"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
