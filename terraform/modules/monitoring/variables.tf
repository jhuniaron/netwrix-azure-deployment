variable "name_prefix" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "alert_email" {
  description = "Email address for metric alert notifications"
  type        = string
}

variable "appgw_id" {
  description = "Resource ID of the Application Gateway (for diagnostic settings)"
  type        = string
}

variable "app_service_id" {
  description = "Resource ID of the App Service (for diagnostic settings and alerts)"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
