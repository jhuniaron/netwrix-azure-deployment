output "law_id" {
  description = "Resource ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "app_insights_id" {
  description = "Resource ID of Application Insights"
  value       = azurerm_application_insights.main.id
}

output "app_insights_connection_string" {
  description = "Application Insights connection string (stored in Key Vault by the key_vault module)"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}
