resource "azurerm_public_ip" "appgw" {
  name                = "pip-appgw-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# WAF Policy — defines the ruleset applied to all traffic
resource "azurerm_web_application_firewall_policy" "main" {
  name                = "wafpol-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  policy_settings {
    enabled                     = true
    mode                        = "Prevention" # Actively blocks; use Detection first if tuning is needed
    request_body_check          = true
    file_upload_limit_in_mb     = 100
    max_request_body_size_in_kb = 128
  }

  managed_rules {
    # OWASP Core Rule Set 3.2 — covers SQLi, XSS, path traversal, RCE, etc.
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
    # Microsoft Bot Manager — blocks known bad bots; allows good bots (Googlebot, etc.)
    managed_rule_set {
      type    = "Microsoft_BotManagerRuleSet"
      version = "1.0"
    }
  }

  # Custom rule: block requests from known vulnerability scanner tools
  custom_rules {
    name      = "BlockKnownScanners" # Azure WAF custom rule names: alphanumeric only, no hyphens
    priority  = 1
    rule_type = "MatchRule"
    action    = "Block"

    match_conditions {
      match_variables {
        variable_name = "RequestHeaders"
        selector      = "User-Agent"
      }
      operator           = "Contains"
      negation_condition = false
      match_values       = ["sqlmap", "nikto", "nmap", "masscan", "zgrab"]
    }
  }
}

locals {
  backend_pool_name    = "backend-${var.name_prefix}"
  frontend_ip_name     = "frontendip-${var.name_prefix}"
  port_https           = "port-443"
  port_http            = "port-80"
  http_setting_name    = "httpsetting-${var.name_prefix}"
  listener_https       = "listener-https-${var.name_prefix}"
  listener_http        = "listener-http-${var.name_prefix}"
  rule_https           = "rule-https-${var.name_prefix}"
  rule_redirect        = "rule-redirect-${var.name_prefix}"
  probe_name           = "probe-${var.name_prefix}"
  redirect_config_name = "redirect-http-to-https"
}

resource "azurerm_application_gateway" "main" {
  name                = "appgw-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  firewall_policy_id  = azurerm_web_application_firewall_policy.main.id
  tags                = var.tags

  # User-assigned managed identity lets App Gateway pull the TLS cert from Key Vault
  identity {
    type         = "UserAssigned"
    identity_ids = [var.appgw_identity_id]
  }

  sku {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  # CKV_AZURE_218: Custom policy so Checkov can statically verify min_protocol_version = TLSv1_2
  ssl_policy {
    policy_type          = "Custom"
    min_protocol_version = "TLSv1_2"
    cipher_suites = [
      "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
      "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
      "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
    ]
  }

  # WAF_v2 autoscales capacity units — no manual sizing needed
  autoscale_configuration {
    min_capacity = 1
    max_capacity = 10
  }

  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = var.gateway_subnet_id
  }

  frontend_port {
    name = local.port_https
    port = 443
  }

  frontend_port {
    name = local.port_http
    port = 80
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_name
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  # Backend pool — points at the App Service
  backend_address_pool {
    name  = local.backend_pool_name
    fqdns = [var.app_service_hostname]
  }

  # HTTPS backend settings — App Gateway talks to App Service over HTTPS
  backend_http_settings {
    name                                = local.http_setting_name
    cookie_based_affinity               = "Disabled"
    port                                = 443
    protocol                            = "Https"
    request_timeout                     = 30
    host_name                           = var.app_service_hostname
    pick_host_name_from_backend_address = false
    probe_name                          = local.probe_name
  }

  # Health probe — App Gateway checks /health every 30s; removes unhealthy instances
  probe {
    name                = local.probe_name
    host                = var.app_service_hostname
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
    protocol            = "Https"
    path                = "/health"

    match {
      status_code = ["200-399"]
    }
  }

  # TLS certificate is a self-signed cert generated in Key Vault (dev)
  # App Gateway reads it at deploy time using its managed identity
  ssl_certificate {
    name                = "appgw-tls-dev"
    key_vault_secret_id = var.appgw_cert_secret_id
  }

  # HTTPS listener — where real traffic enters
  http_listener {
    name                           = local.listener_https
    frontend_ip_configuration_name = local.frontend_ip_name
    frontend_port_name             = local.port_https
    protocol                       = "Https"
    ssl_certificate_name           = "appgw-tls-dev"
  }

  # HTTP listener — only exists to redirect to HTTPS
  http_listener {
    name                           = local.listener_http
    frontend_ip_configuration_name = local.frontend_ip_name
    frontend_port_name             = local.port_http
    protocol                       = "Http"
  }

  # Route HTTPS traffic to the App Service backend
  request_routing_rule {
    name                       = local.rule_https
    rule_type                  = "Basic"
    priority                   = 100
    http_listener_name         = local.listener_https
    backend_address_pool_name  = local.backend_pool_name
    backend_http_settings_name = local.http_setting_name
  }

  # Redirect all HTTP traffic permanently to HTTPS
  redirect_configuration {
    name                 = local.redirect_config_name
    redirect_type        = "Permanent"
    target_listener_name = local.listener_https
    include_path         = true
    include_query_string = true
  }

  request_routing_rule {
    name                        = local.rule_redirect
    rule_type                   = "Basic"
    priority                    = 200
    http_listener_name          = local.listener_http
    redirect_configuration_name = local.redirect_config_name
  }
}
