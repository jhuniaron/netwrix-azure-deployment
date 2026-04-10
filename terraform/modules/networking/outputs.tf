output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "location" {
  description = "Azure region of the resource group"
  value       = azurerm_resource_group.main.location
}

output "vnet_id" {
  description = "Resource ID of the Virtual Network"
  value       = azurerm_virtual_network.main.id
}

output "gateway_subnet_id" {
  description = "Resource ID of the Application Gateway subnet"
  value       = azurerm_subnet.gateway.id
}

output "gateway_subnet_cidr" {
  description = "CIDR of the Application Gateway subnet"
  value       = var.gateway_subnet_cidr
}

output "app_subnet_id" {
  description = "Resource ID of the App Service VNet Integration subnet"
  value       = azurerm_subnet.app.id
}

output "data_subnet_id" {
  description = "Resource ID of the SQL Private Endpoint subnet"
  value       = azurerm_subnet.data.id
}

output "pe_subnet_id" {
  description = "Resource ID of the Key Vault Private Endpoint subnet"
  value       = azurerm_subnet.private_endpoints.id
}

output "sql_dns_zone_id" {
  description = "Resource ID of the SQL Private DNS Zone"
  value       = azurerm_private_dns_zone.zones["sql"].id
}

output "keyvault_dns_zone_id" {
  description = "Resource ID of the Key Vault Private DNS Zone"
  value       = azurerm_private_dns_zone.zones["keyvault"].id
}
