output "app_name" {
  description = "Name of the App Service"
  value       = azurerm_linux_web_app.main.name
}

output "app_id" {
  description = "Resource ID of the App Service"
  value       = azurerm_linux_web_app.main.id
}

output "principal_id" {
  description = "Object ID of the App Service system-assigned managed identity"
  value       = azurerm_linux_web_app.main.identity[0].principal_id
}

output "default_hostname" {
  description = "Default hostname of the App Service (azurewebsites.net)"
  value       = azurerm_linux_web_app.main.default_hostname
}
