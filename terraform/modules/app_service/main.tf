resource "azurerm_service_plan" "main" {
  name                = "plan-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = var.sku_name
  tags                = var.tags
}

resource "azurerm_linux_web_app" "main" {
  name                      = "app-${var.name_prefix}"
  location                  = var.location
  resource_group_name       = var.resource_group_name
  service_plan_id           = azurerm_service_plan.main.id
  virtual_network_subnet_id = var.app_subnet_id  # All outbound traffic goes via the VNet
  https_only                = true
  tags                      = var.tags

  # System-assigned Managed Identity — Azure creates this automatically.
  # Used to authenticate to Key Vault and SQL without any password.
  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on           = true
    http2_enabled       = true
    ftps_state          = "Disabled"      # Only git/zip deploy via HTTPS
    minimum_tls_version = "1.2"
    health_check_path   = "/health"

    application_stack {
      dotnet_version = "10.0"
    }

    # FIREWALL: Only the Application Gateway subnet can reach this app.
    # Any direct request to *.azurewebsites.net returns 403.
    ip_restriction {
      name       = "allow-appgateway-only"
      ip_address = var.gateway_subnet_cidr
      action     = "Allow"
      priority   = 100
    }

    ip_restriction_default_action = "Deny"
  }

  app_settings = {
    # Key Vault References — Azure resolves these at runtime using Managed Identity.
    # The actual connection string never appears here in plaintext.
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = "@Microsoft.KeyVault(SecretUri=${var.appinsights_secret_uri})"
    "ConnectionStrings__DefaultConnection"  = "@Microsoft.KeyVault(SecretUri=${var.db_connstring_secret_uri})"

    "ASPNETCORE_ENVIRONMENT" = var.environment

    # Force all outbound traffic through the VNet integration subnet
    "WEBSITE_VNET_ROUTE_ALL" = "1"
  }

  logs {
    http_logs {
      file_system {
        retention_in_days = 30
        retention_in_mb   = 35
      }
    }
    application_logs {
      file_system_level = "Warning"
    }
  }
}

# Autoscale: scale out when CPU > 70% for 5 mins; scale in when CPU < 30% for 10 mins
resource "azurerm_monitor_autoscale_setting" "app" {
  name                = "autoscale-${var.name_prefix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_service_plan.main.id
  tags                = var.tags

  profile {
    name = "default"

    capacity {
      default = 1
      minimum = 1
      maximum = 10
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 30
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }
}
