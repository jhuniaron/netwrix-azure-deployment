output "key_vault_id" {
  description = "Resource ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "db_connstring_secret_uri" {
  description = "Versionless URI of the db-connection-string secret (used in App Service Key Vault Reference)"
  value       = azurerm_key_vault_secret.db_connection_string.versionless_id
}

output "appinsights_connstring_secret_uri" {
  description = "Versionless URI of the appinsights-connection-string secret"
  value       = azurerm_key_vault_secret.appinsights_connection_string.versionless_id
}
