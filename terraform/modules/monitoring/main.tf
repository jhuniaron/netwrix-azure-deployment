resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 90
  tags                = var.tags
}

# Workspace-based App Insights — telemetry flows into the same Log Analytics
# workspace, enabling unified Kusto queries across all services
resource "azurerm_application_insights" "main" {
  name                = "appi-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = var.tags
}

# Forward Application Gateway access + firewall logs to Log Analytics
resource "azurerm_monitor_diagnostic_setting" "appgw" {
  name                       = "diag-appgw-${var.name_prefix}"
  target_resource_id         = var.appgw_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log { category = "ApplicationGatewayAccessLog" }
  enabled_log { category = "ApplicationGatewayFirewallLog" }

  enabled_metric {
    category = "AllMetrics"
  }
}

# Forward App Service HTTP and application logs to Log Analytics
resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "diag-app-${var.name_prefix}"
  target_resource_id         = var.app_service_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log { category = "AppServiceHTTPLogs" }
  enabled_log { category = "AppServiceConsoleLogs" }
  enabled_log { category = "AppServiceAppLogs" }

  enabled_metric {
    category = "AllMetrics"
  }
}

# Alert when 5xx errors exceed 10 in a 5-minute window
resource "azurerm_monitor_metric_alert" "http_5xx" {
  name                = "alert-http5xx-${var.name_prefix}"
  resource_group_name = var.resource_group_name
  scopes              = [var.app_service_id]
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops.id
  }
}

resource "azurerm_monitor_action_group" "ops" {
  name                = "ag-ops-${var.name_prefix}"
  resource_group_name = var.resource_group_name
  short_name          = "ops"
  tags                = var.tags

  email_receiver {
    name                    = "ops-email"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
}
