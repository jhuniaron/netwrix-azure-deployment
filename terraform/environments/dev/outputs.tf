output "app_gateway_public_ip" {
  description = "Public IP of the Application Gateway — use this to access the app"
  value       = module.waf.public_ip_address
}

output "app_service_hostname" {
  description = "App Service internal hostname (direct access is blocked — use App Gateway IP)"
  value       = module.app_service.default_hostname
}

output "sql_server_fqdn" {
  description = "Fully qualified domain name of the SQL Server"
  value       = module.database.sql_server_fqdn
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = module.key_vault.key_vault_uri
}
