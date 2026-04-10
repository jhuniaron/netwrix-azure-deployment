# Azure Terraform-Based .NET 10 Deployment — Project Guide

> **Role:** Senior DevOps / Cloud Engineer candidate — Netwrix Technical Assessment
> **Stack:** Azure · Terraform · GitHub Actions · .NET 10 on Linux

---

## Table of Contents

1. [Architecture Proposal](#1-architecture-proposal)
2. [Prerequisites & Local Setup](#2-prerequisites--local-setup)
3. [Repository Structure](#3-repository-structure)
4. [Terraform IaC](#4-terraform-iac)
   - 4.1 Remote State Bootstrap
   - 4.2 Versions & Providers
   - 4.3 Networking Module
   - 4.4 App Service Module
   - 4.5 Database Module
   - 4.6 Application Gateway / WAF Module
   - 4.7 Key Vault Module
   - 4.8 Monitoring Module
   - 4.9 Root Environment Composition
5. [CI/CD Pipeline — GitHub Actions](#5-cicd-pipeline--github-actions)
6. [Security Implementation Notes](#6-security-implementation-notes)
7. [Monitoring & Observability](#7-monitoring--observability)
8. [Presentation Talking Points](#8-presentation-talking-points)

---

## 1. Architecture Proposal

> This section is the **1–2 page architecture document** required by the assessment. Adapt it for your written submission.

### 1.1 Selected Azure Services & Rationale

| Layer | Service | Why |
|---|---|---|
| Compute | **Azure App Service (Linux, P1v3)** | Managed PaaS; native .NET support; built-in deployment slots for zero-downtime swaps; outbound VNet Integration available from Basic+ tier; no container orchestration overhead for a single app |
| Database | **Azure SQL Database (General Purpose, Serverless)** | Fully managed; native Azure AD auth eliminates SQL passwords; Private Endpoint support; auto-pause during dev reduces cost; transparent data encryption on by default |
| WAF / Ingress | **Azure Application Gateway v2 with WAF_v2 SKU** | Layer-7 load balancing + inline WAF (OWASP CRS 3.2); SSL offload; custom WAF rules; sits entirely inside the VNet; autoscaling via min/max capacity units |
| Networking | **Azure Virtual Network + NSGs** | Explicit subnet segmentation; NSG rules enforce least-privilege east-west traffic; no reliance on default-allow behaviour |
| Secrets | **Azure Key Vault (RBAC model)** | Single source of truth for connection strings, app secrets, certificates; App Service Key Vault references mean secrets never land in App Settings in plaintext |
| Identity | **System-Assigned Managed Identity** | Zero stored credentials; works natively with Key Vault RBAC and Azure AD SQL authentication |
| Logging | **Log Analytics Workspace + Application Insights** | Centralised log sink for all services; Application Insights provides APM, distributed tracing, failure analysis, and availability tests; Kusto queries for alerting |
| CI/CD Auth | **Workload Identity Federation (OIDC)** | GitHub Actions authenticates to Azure without storing long-lived secrets; federated credential scoped to repo + branch |

### 1.2 Traffic Flow

```
Internet
   │
   ▼
Azure Application Gateway – WAF_v2  (gateway-subnet 10.0.0.0/26)
  • TLS termination (public cert via Azure-managed or Key Vault cert)
  • OWASP CRS 3.2 inspection
  • HTTP → HTTPS redirect rule
   │
   │  (HTTPS, host header preserved)
   ▼
Azure App Service – Linux / .NET 10   (outbound via app-subnet VNet Integration)
  • App Service Access Restriction: ONLY gateway-subnet allowed inbound
  • Reads secrets via Key Vault references (Key Vault private endpoint)
  • Connects to database via private endpoint
   │                          │
   ▼                          ▼
Azure SQL Database       Azure Key Vault
(data-subnet PE)         (pe-subnet PE)
No public endpoint       No public endpoint

All diagnostic logs → Log Analytics Workspace → Application Insights / Alerts
```

### 1.3 Network Boundaries

| Subnet | CIDR | Resources | NSG Rules (key) |
|---|---|---|---|
| `snet-gateway` | 10.0.0.0/26 | Application Gateway | Inbound: 443 from Internet, 65200-65535 (health probes) |
| `snet-app` | 10.0.1.0/24 | App Service VNet Integration | Outbound: 443 to data/pe subnets only |
| `snet-data` | 10.0.2.0/28 | SQL Private Endpoint | Inbound: 1433 from snet-app only |
| `snet-pe` | 10.0.3.0/28 | Key Vault Private Endpoint | Inbound: 443 from snet-app only |

Private DNS Zones are linked to the VNet to resolve `*.database.windows.net` and `*.vaultcore.azure.net` to private IPs.

### 1.4 Identity Model

```
GitHub Actions Workflow
  └─ OIDC → Azure AD Federated Credential → Service Principal
       └─ Role: Contributor (scoped to resource group)

App Service (System-Assigned Managed Identity)
  ├─ Key Vault: Key Vault Secrets User (RBAC)
  └─ SQL Database: database user mapped to MI (no password)

Terraform Service Principal
  └─ Role: Contributor on resource group + User Access Administrator
           (to assign MI roles)
```

No passwords or shared keys are stored anywhere in GitHub secrets or App Settings.

### 1.5 Key Security Controls

- **WAF**: OWASP CRS 3.2 in Prevention mode; custom rule to block common scanner UAs
- **TLS 1.2+ enforced** on App Service (`minimum_tls_version = "1.2"`) and Application Gateway
- **FTPS disabled** on App Service
- **Private Endpoints** for SQL and Key Vault — no public network access
- **App Service Access Restriction** — only Application Gateway subnet can reach the app
- **Key Vault References** — secrets injected at runtime, never stored in App Settings
- **Managed Identity** — no stored credentials anywhere in the pipeline or app
- **Defender for SQL** — threat detection and vulnerability assessment
- **Soft-delete + purge protection** on Key Vault
- **Checkov** scans Terraform before every apply (pipeline security gate)
- **Gitleaks** scans every commit for accidentally committed secrets

### 1.6 Scalability

- **App Service Plan autoscale**: scale-out rules based on CPU > 70% for 5 minutes (3→10 instances); scale-in when CPU < 30% for 10 minutes
- **Application Gateway**: WAF_v2 scales capacity units automatically (min 1, max 10)
- **SQL Database Serverless**: auto-scales vCores (min 0.5, max 4) and auto-pauses — upgrade to Hyperscale or Elastic Pool for higher throughput
- **For larger scale**: swap App Service for **Azure Container Apps** (supports KEDA-based event-driven autoscale) or **AKS** (full control, multi-region active-active via Traffic Manager)
- **CDN / caching layer**: Azure Front Door in front of App Gateway for global distribution and static asset caching — not included here for scope reasons

### 1.7 What's Missing & What's Next

| Gap | Priority | Next Step |
|---|---|---|
| Multi-region / DR | High | Add a paired region, geo-replication on SQL, Traffic Manager or Front Door for failover |
| App Service Environment (ASE) | Medium | If full network isolation (no public App Service endpoints at all) is required, migrate to ASE v3 |
| Container strategy | Medium | Containerise the app, push to Azure Container Registry, deploy to Container Apps or AKS for better density and portability |
| Integration tests in pipeline | Medium | Add a post-deploy smoke test job (health check hit, basic API assertions) |
| Azure Policy | Medium | Enforce tagging, allowed locations, and required diagnostic settings organisation-wide |
| Cost management | Low | Budget alerts via Azure Cost Management; reserved capacity on SQL and App Service after baseline load is known |

---

## 2. Prerequisites & Local Setup

```bash
# Required tooling
az --version          # Azure CLI >= 2.60
terraform -version    # >= 1.9
dotnet --version      # >= 10.0
git --version

# Login to Azure
az login
az account set --subscription "<your-subscription-id>"
```

**GitHub repo secrets required:**

| Secret | Description |
|---|---|
| `AZURE_CLIENT_ID` | Service Principal app ID (OIDC) |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription |
| `TF_STATE_RG` | Resource group name for Terraform state storage account |
| `TF_STATE_SA` | Storage account name for Terraform state |
| `SQL_ADMIN_LOGIN` | SQL Server admin username (bootstrapping only) |
| `SQL_ADMIN_PASSWORD` | SQL Server admin password (bootstrapping only — rotated post-deploy) |

**GitHub repo variables required:**

| Variable | Description |
|---|---|
| `AZURE_WEBAPP_NAME` | App Service name (must match Terraform output) |
| `AZURE_RESOURCE_GROUP` | Resource group for the deployment |

---

## 3. Repository Structure

```
.
├── .github/
│   └── workflows/
│       └── deploy.yml                  # Main CI/CD pipeline
├── terraform/
│   ├── bootstrap/                      # One-time: creates remote state resources
│   │   └── main.tf
│   ├── environments/
│   │   ├── dev/
│   │   │   ├── main.tf                 # Root module for dev
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── terraform.tfvars        # Non-sensitive dev values
│   │   └── prod/
│   │       └── (same structure)
│   └── modules/
│       ├── networking/                 # VNet, subnets, NSGs, private DNS zones
│       ├── app_service/                # App Service Plan + Linux Web App
│       ├── database/                   # Azure SQL Server + Database + PE
│       ├── waf/                        # Application Gateway WAF_v2
│       ├── key_vault/                  # Key Vault + RBAC + private endpoint
│       └── monitoring/                 # Log Analytics + App Insights + alerts
├── Netwrix.DevOps.Test.sln
└── Netwrix.DevOps.Test.App/
    └── Netwrix.DevOps.Test.App.csproj
```

---

## 4. Terraform IaC

### 4.1 Remote State Bootstrap

Run once manually before any pipeline executes. This creates the storage account that will hold `terraform.tfstate`.

```hcl
# terraform/bootstrap/main.tf
resource "azurerm_resource_group" "tfstate" {
  name     = "rg-netwrix-tfstate"
  location = "Australia East"
}

resource "azurerm_storage_account" "tfstate" {
  name                            = "stnetwrixtfstate"   # must be globally unique
  resource_group_name             = azurerm_resource_group.tfstate.name
  location                        = azurerm_resource_group.tfstate.location
  account_tier                    = "Standard"
  account_replication_type        = "GRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = true
    delete_retention_policy { days = 30 }
  }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.tfstate.name
  container_access_type = "private"
}
```

### 4.2 Versions & Providers

```hcl
# terraform/environments/dev/versions.tf
terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "azurerm" {
    # Values injected at `terraform init` via -backend-config flags in pipeline
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}
```

### 4.3 Networking Module

```hcl
# terraform/modules/networking/main.tf

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.name_prefix}"
  address_space       = [var.vnet_cidr]  # e.g. "10.0.0.0/16"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

# --- Subnets ---

resource "azurerm_subnet" "gateway" {
  name                 = "snet-gateway"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.gateway_subnet_cidr]  # "10.0.0.0/26"
}

resource "azurerm_subnet" "app" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.app_subnet_cidr]       # "10.0.1.0/24"

  delegation {
    name = "appservice-delegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "data" {
  name                              = "snet-data"
  resource_group_name               = azurerm_resource_group.main.name
  virtual_network_name              = azurerm_virtual_network.main.name
  address_prefixes                  = [var.data_subnet_cidr]  # "10.0.2.0/28"
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_subnet" "private_endpoints" {
  name                              = "snet-pe"
  resource_group_name               = azurerm_resource_group.main.name
  virtual_network_name              = azurerm_virtual_network.main.name
  address_prefixes                  = [var.pe_subnet_cidr]  # "10.0.3.0/28"
  private_endpoint_network_policies = "Disabled"
}

# --- NSGs ---

resource "azurerm_network_security_group" "gateway" {
  name                = "nsg-gateway"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "allow-https-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-http-redirect"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  # Required for Application Gateway health probes
  security_rule {
    name                       = "allow-appgw-management"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "gateway" {
  subnet_id                 = azurerm_subnet.gateway.id
  network_security_group_id = azurerm_network_security_group.gateway.id
}

# --- Private DNS Zones ---

locals {
  private_dns_zones = {
    sql       = "privatelink.database.windows.net"
    keyvault  = "privatelink.vaultcore.azure.net"
  }
}

resource "azurerm_private_dns_zone" "zones" {
  for_each            = local.private_dns_zones
  name                = each.value
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "links" {
  for_each              = local.private_dns_zones
  name                  = "link-${each.key}"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.zones[each.key].name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false
}

# Outputs (used by other modules)
output "resource_group_name"    { value = azurerm_resource_group.main.name }
output "location"               { value = azurerm_resource_group.main.location }
output "vnet_id"                { value = azurerm_virtual_network.main.id }
output "gateway_subnet_id"      { value = azurerm_subnet.gateway.id }
output "app_subnet_id"          { value = azurerm_subnet.app.id }
output "data_subnet_id"         { value = azurerm_subnet.data.id }
output "pe_subnet_id"           { value = azurerm_subnet.private_endpoints.id }
output "sql_dns_zone_id"        { value = azurerm_private_dns_zone.zones["sql"].id }
output "keyvault_dns_zone_id"   { value = azurerm_private_dns_zone.zones["keyvault"].id }
```

### 4.4 App Service Module

```hcl
# terraform/modules/app_service/main.tf

resource "azurerm_service_plan" "main" {
  name                = "plan-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = var.sku_name  # "P1v3" minimum for production
  tags                = var.tags
}

resource "azurerm_linux_web_app" "main" {
  name                      = "app-${var.name_prefix}"
  location                  = var.location
  resource_group_name       = var.resource_group_name
  service_plan_id           = azurerm_service_plan.main.id
  virtual_network_subnet_id = var.app_subnet_id   # Outbound VNet Integration
  https_only                = true
  tags                      = var.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on           = true
    http2_enabled       = true
    ftps_state          = "Disabled"
    minimum_tls_version = "1.2"
    health_check_path   = "/health"

    application_stack {
      dotnet_version = "10.0"
    }

    # Enforce inbound traffic comes ONLY from Application Gateway subnet
    ip_restriction {
      name       = "allow-appgateway-only"
      ip_address = "${var.gateway_subnet_cidr}"
      action     = "Allow"
      priority   = 100
    }

    ip_restriction_default_action = "Deny"
  }

  app_settings = {
    # Key Vault References — secrets never stored in plain text
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = "@Microsoft.KeyVault(SecretUri=${var.appinsights_secret_uri})"
    "ConnectionStrings__DefaultConnection"  = "@Microsoft.KeyVault(SecretUri=${var.db_connstring_secret_uri})"
    "ASPNETCORE_ENVIRONMENT"                = var.environment

    # Prevent App Service from routing outbound traffic via default gateway
    "WEBSITE_VNET_ROUTE_ALL" = "1"
  }

  logs {
    http_logs {
      retention_in_days = 30
    }
    application_logs {
      file_system_level = "Warning"
    }
  }
}

# Autoscale policy
resource "azurerm_monitor_autoscale_setting" "app" {
  name                = "autoscale-${var.name_prefix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_service_plan.main.id

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
        value     = 1
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
        value     = 1
        cooldown  = "PT10M"
      }
    }
  }
}

output "app_name"       { value = azurerm_linux_web_app.main.name }
output "app_id"         { value = azurerm_linux_web_app.main.id }
output "principal_id"   { value = azurerm_linux_web_app.main.identity[0].principal_id }
output "default_hostname" { value = azurerm_linux_web_app.main.default_hostname }
```

### 4.5 Database Module

```hcl
# terraform/modules/database/main.tf

resource "random_password" "sql_admin" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}:?"
}

resource "azurerm_mssql_server" "main" {
  name                         = "sql-${var.name_prefix}"
  resource_group_name          = var.resource_group_name
  location                     = var.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_login
  administrator_login_password = random_password.sql_admin.result
  minimum_tls_version          = "1.2"
  tags                         = var.tags

  # Disable public access — only reachable via private endpoint
  public_network_access_enabled = false

  azuread_administrator {
    login_username = var.aad_admin_login
    object_id      = var.aad_admin_object_id
    azuread_authentication_only = false  # set true once MI auth is confirmed working
  }
}

resource "azurerm_mssql_database" "main" {
  name         = "sqldb-${var.name_prefix}"
  server_id    = azurerm_mssql_server.main.id
  collation    = "SQL_Latin1_General_CP1_CI_AS"
  license_type = "LicenseIncluded"
  sku_name     = "GP_S_Gen5_1"    # General Purpose Serverless, 1 vCore
  max_size_gb  = 32
  tags         = var.tags

  auto_pause_delay_in_minutes = 60  # Pause after 60 min idle (dev/test)
  min_capacity                = 0.5
}

# Defender for SQL
resource "azurerm_mssql_server_security_alert_policy" "main" {
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mssql_server.main.name
  state               = "Enabled"
}

resource "azurerm_mssql_server_vulnerability_assessment" "main" {
  server_security_alert_policy_id = azurerm_mssql_server_security_alert_policy.main.id
  storage_container_path          = "${var.storage_account_blob_endpoint}vulnerability-assessment/"

  recurring_scans {
    enabled                   = true
    email_subscription_admins = true
  }
}

# Private Endpoint
resource "azurerm_private_endpoint" "sql" {
  name                = "pe-sql-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.data_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-sql"
    private_connection_resource_id = azurerm_mssql_server.main.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-group-sql"
    private_dns_zone_ids = [var.sql_dns_zone_id]
  }
}

output "sql_server_fqdn"   { value = azurerm_mssql_server.main.fully_qualified_domain_name }
output "sql_database_name" { value = azurerm_mssql_database.main.name }
```

### 4.6 Application Gateway / WAF Module

```hcl
# terraform/modules/waf/main.tf

resource "azurerm_public_ip" "appgw" {
  name                = "pip-appgw-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_web_application_firewall_policy" "main" {
  name                = "wafpol-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  policy_settings {
    enabled                     = true
    mode                        = "Prevention"  # Detection for initial rollout; switch to Prevention once verified
    request_body_check          = true
    file_upload_limit_in_mb     = 100
    max_request_body_size_in_kb = 128
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
    managed_rule_set {
      type    = "Microsoft_BotManagerRuleSet"
      version = "1.0"
    }
  }

  custom_rules {
    name      = "block-known-scanners"
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
      match_values       = ["sqlmap", "nikto", "nmap", "masscan"]
    }
  }
}

locals {
  backend_address_pool_name      = "backend-${var.name_prefix}"
  frontend_ip_config_name        = "frontendip-${var.name_prefix}"
  frontend_port_name_https       = "port-443"
  frontend_port_name_http        = "port-80"
  http_setting_name              = "httpsetting-${var.name_prefix}"
  https_listener_name            = "listener-https-${var.name_prefix}"
  http_listener_name             = "listener-http-${var.name_prefix}"
  request_routing_rule_https     = "rule-https-${var.name_prefix}"
  request_routing_rule_redirect  = "rule-redirect-${var.name_prefix}"
  health_probe_name              = "probe-${var.name_prefix}"
  ssl_cert_name                  = "cert-${var.name_prefix}"
}

resource "azurerm_application_gateway" "main" {
  name                = "appgw-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  firewall_policy_id  = azurerm_web_application_firewall_policy.main.id
  tags                = var.tags

  sku {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  autoscale_configuration {
    min_capacity = 1
    max_capacity = 10
  }

  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = var.gateway_subnet_id
  }

  frontend_port {
    name = local.frontend_port_name_https
    port = 443
  }

  frontend_port {
    name = local.frontend_port_name_http
    port = 80
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_config_name
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  backend_address_pool {
    name  = local.backend_address_pool_name
    fqdns = [var.app_service_hostname]  # e.g. app-netwrix-dev.azurewebsites.net
  }

  backend_http_settings {
    name                                = local.http_setting_name
    cookie_based_affinity               = "Disabled"
    port                                = 443
    protocol                            = "Https"
    request_timeout                     = 30
    host_name                           = var.app_service_hostname
    pick_host_name_from_backend_address = false

    probe_name = local.health_probe_name
  }

  probe {
    name                = local.health_probe_name
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

  ssl_certificate {
    name                = local.ssl_cert_name
    key_vault_secret_id = var.ssl_cert_keyvault_secret_id
  }

  http_listener {
    name                           = local.https_listener_name
    frontend_ip_configuration_name = local.frontend_ip_config_name
    frontend_port_name             = local.frontend_port_name_https
    protocol                       = "Https"
    ssl_certificate_name           = local.ssl_cert_name
  }

  http_listener {
    name                           = local.http_listener_name
    frontend_ip_configuration_name = local.frontend_ip_config_name
    frontend_port_name             = local.frontend_port_name_http
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.request_routing_rule_https
    rule_type                  = "Basic"
    priority                   = 100
    http_listener_name         = local.https_listener_name
    backend_address_pool_name  = local.backend_address_pool_name
    backend_http_settings_name = local.http_setting_name
  }

  # HTTP → HTTPS redirect
  redirect_configuration {
    name                 = "redirect-http-to-https"
    redirect_type        = "Permanent"
    target_listener_name = local.https_listener_name
    include_path         = true
    include_query_string = true
  }

  request_routing_rule {
    name                        = local.request_routing_rule_redirect
    rule_type                   = "Basic"
    priority                    = 200
    http_listener_name          = local.http_listener_name
    redirect_configuration_name = "redirect-http-to-https"
  }
}

output "public_ip_address" { value = azurerm_public_ip.appgw.ip_address }
output "appgw_id"          { value = azurerm_application_gateway.main.id }
```

### 4.7 Key Vault Module

```hcl
# terraform/modules/key_vault/main.tf

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "main" {
  name                       = "kv-${var.name_prefix}"  # max 24 chars, globally unique
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true         # RBAC model instead of legacy access policies
  soft_delete_retention_days = 90
  purge_protection_enabled   = true
  tags                       = var.tags

  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = []  # Access via private endpoint only
    ip_rules                   = []
  }
}

# Grant the App Service Managed Identity access to read secrets
resource "azurerm_role_assignment" "app_kv_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.app_service_principal_id
}

# Grant Terraform SP access to create/update secrets during deployment
resource "azurerm_role_assignment" "terraform_kv_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Store secrets (referenced by App Service via Key Vault References)
resource "azurerm_key_vault_secret" "db_connection_string" {
  name         = "db-connection-string"
  value        = var.db_connection_string
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.terraform_kv_officer]
}

resource "azurerm_key_vault_secret" "appinsights_connection_string" {
  name         = "appinsights-connection-string"
  value        = var.appinsights_connection_string
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [azurerm_role_assignment.terraform_kv_officer]
}

# Private Endpoint for Key Vault
resource "azurerm_private_endpoint" "kv" {
  name                = "pe-kv-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-kv"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-group-kv"
    private_dns_zone_ids = [var.keyvault_dns_zone_id]
  }
}

output "key_vault_id"                       { value = azurerm_key_vault.main.id }
output "key_vault_uri"                      { value = azurerm_key_vault.main.vault_uri }
output "db_connstring_secret_uri"           { value = azurerm_key_vault_secret.db_connection_string.versionless_id }
output "appinsights_connstring_secret_uri"  { value = azurerm_key_vault_secret.appinsights_connection_string.versionless_id }
```

### 4.8 Monitoring Module

```hcl
# terraform/modules/monitoring/main.tf

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 90
  tags                = var.tags
}

resource "azurerm_application_insights" "main" {
  name                = "appi-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = var.tags
}

# Diagnostic settings — forward App Gateway logs to Log Analytics
resource "azurerm_monitor_diagnostic_setting" "appgw" {
  name                       = "diag-appgw"
  target_resource_id         = var.appgw_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log { category = "ApplicationGatewayAccessLog" }
  enabled_log { category = "ApplicationGatewayFirewallLog" }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Diagnostic settings — App Service
resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "diag-app"
  target_resource_id         = var.app_service_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log { category = "AppServiceHTTPLogs" }
  enabled_log { category = "AppServiceConsoleLogs" }
  enabled_log { category = "AppServiceAppLogs" }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Example alert — 5xx error rate spike
resource "azurerm_monitor_metric_alert" "http_5xx" {
  name                = "alert-http5xx-${var.name_prefix}"
  resource_group_name = var.resource_group_name
  scopes              = [var.app_service_id]
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

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

  email_receiver {
    name          = "ops-email"
    email_address = var.alert_email
  }
}

output "law_id"                     { value = azurerm_log_analytics_workspace.main.id }
output "app_insights_id"            { value = azurerm_application_insights.main.id }
output "app_insights_conn_string"   { value = azurerm_application_insights.main.connection_string }
```

### 4.9 Root Environment Composition

```hcl
# terraform/environments/dev/main.tf

module "networking" {
  source              = "../../modules/networking"
  name_prefix         = "${var.project}-${var.environment}"
  resource_group_name = "rg-${var.project}-${var.environment}"
  location            = var.location
  vnet_cidr           = "10.0.0.0/16"
  gateway_subnet_cidr = "10.0.0.0/26"
  app_subnet_cidr     = "10.0.1.0/24"
  data_subnet_cidr    = "10.0.2.0/28"
  pe_subnet_cidr      = "10.0.3.0/28"
  tags                = local.tags
}

module "monitoring" {
  source              = "../../modules/monitoring"
  name_prefix         = "${var.project}-${var.environment}"
  location            = module.networking.location
  resource_group_name = module.networking.resource_group_name
  alert_email         = var.alert_email
  appgw_id            = module.waf.appgw_id
  app_service_id      = module.app_service.app_id
  tags                = local.tags
}

module "key_vault" {
  source                     = "../../modules/key_vault"
  name_prefix                = "${var.project}-${var.environment}"
  location                   = module.networking.location
  resource_group_name        = module.networking.resource_group_name
  pe_subnet_id               = module.networking.pe_subnet_id
  keyvault_dns_zone_id       = module.networking.keyvault_dns_zone_id
  app_service_principal_id   = module.app_service.principal_id
  db_connection_string       = "Server=tcp:${module.database.sql_server_fqdn};Database=${module.database.sql_database_name};Authentication=Active Directory Default;"
  appinsights_connection_string = module.monitoring.app_insights_conn_string
  tags                       = local.tags
}

module "app_service" {
  source                     = "../../modules/app_service"
  name_prefix                = "${var.project}-${var.environment}"
  location                   = module.networking.location
  resource_group_name        = module.networking.resource_group_name
  app_subnet_id              = module.networking.app_subnet_id
  gateway_subnet_cidr        = "10.0.0.0/26"
  sku_name                   = var.app_service_sku
  environment                = var.environment
  appinsights_secret_uri     = module.key_vault.appinsights_connstring_secret_uri
  db_connstring_secret_uri   = module.key_vault.db_connstring_secret_uri
  tags                       = local.tags
}

module "database" {
  source              = "../../modules/database"
  name_prefix         = "${var.project}-${var.environment}"
  location            = module.networking.location
  resource_group_name = module.networking.resource_group_name
  data_subnet_id      = module.networking.data_subnet_id
  sql_dns_zone_id     = module.networking.sql_dns_zone_id
  sql_admin_login     = var.sql_admin_login
  aad_admin_login     = var.aad_admin_login
  aad_admin_object_id = var.aad_admin_object_id
  tags                = local.tags
}

module "waf" {
  source               = "../../modules/waf"
  name_prefix          = "${var.project}-${var.environment}"
  location             = module.networking.location
  resource_group_name  = module.networking.resource_group_name
  gateway_subnet_id    = module.networking.gateway_subnet_id
  app_service_hostname = module.app_service.default_hostname
  ssl_cert_keyvault_secret_id = var.ssl_cert_keyvault_secret_id
  tags                 = local.tags
}

locals {
  tags = {
    project     = var.project
    environment = var.environment
    managed_by  = "terraform"
  }
}
```

---

## 5. CI/CD Pipeline — GitHub Actions

### 5.1 Pipeline Overview

```
Push to main / PR to main
        │
        ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  build-test     │───▶│  security-gates  │───▶│ terraform-plan  │
│  dotnet build   │    │  Gitleaks        │    │ tf init+plan    │
│  dotnet test    │    │  Checkov (SAST)  │    │ upload tfplan   │
│  dotnet publish │    │  CodeQL upload   │    └───────┬─────────┘
│  zip artifact   │    └──────────────────┘            │ (push to main only)
└─────────────────┘                                    ▼
                                            ┌─────────────────────┐
                                            │  manual-approval    │
                                            │  (GitHub Env gate)  │
                                            └───────┬─────────────┘
                                                    │
                                                    ▼
                                            ┌─────────────────────┐
                                            │  terraform-apply    │
                                            └───────┬─────────────┘
                                                    │
                                                    ▼
                                            ┌─────────────────────┐
                                            │  deploy-to-azure    │
                                            │  az webapp deploy   │
                                            │  post-deploy smoke  │
                                            └─────────────────────┘
```

### 5.2 Full Pipeline YAML

```yaml
# .github/workflows/deploy.yml
name: Build, Secure, and Deploy

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  id-token: write     # Required for OIDC authentication to Azure
  contents: read
  security-events: write  # Required for CodeQL SARIF upload

env:
  SOLUTION_FILE:    Netwrix.DevOps.Test.sln
  APP_PROJECT:      Netwrix.DevOps.Test.App
  ARTIFACT_NAME:    Netwrix.DevOps.Test.App.zip
  TF_WORKING_DIR:   terraform/environments/dev
  DOTNET_VERSION:   "10.0.x"
  TF_VERSION:       "1.9.x"

jobs:
  # ------------------------------------------------------------------
  # JOB 1: Build, test, and package the .NET app
  # ------------------------------------------------------------------
  build-test:
    name: Build & Test
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup .NET ${{ env.DOTNET_VERSION }}
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: ${{ env.DOTNET_VERSION }}

      - name: Restore dependencies
        run: dotnet restore ${{ env.SOLUTION_FILE }}

      - name: Build (Release)
        run: dotnet build ${{ env.SOLUTION_FILE }} --no-restore --configuration Release

      - name: Run tests
        run: |
          dotnet test ${{ env.SOLUTION_FILE }} \
            --no-build \
            --configuration Release \
            --verbosity normal \
            --logger "trx;LogFileName=test-results.trx" \
            --collect:"XPlat Code Coverage"

      - name: Publish (Release)
        run: |
          dotnet publish ${{ env.APP_PROJECT }}/${{ env.APP_PROJECT }}.csproj \
            --configuration Release \
            --output ./publish \
            --no-build

      - name: Package artifact
        run: zip -r ${{ env.ARTIFACT_NAME }} ./publish/

      - name: Upload build artifact
        uses: actions/upload-artifact@v4
        with:
          name: app-package
          path: ${{ env.ARTIFACT_NAME }}
          retention-days: 7

  # ------------------------------------------------------------------
  # JOB 2: Security gates — must pass before infrastructure changes
  # ------------------------------------------------------------------
  security-gates:
    name: Security Gates
    runs-on: ubuntu-latest
    needs: build-test

    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Full history for Gitleaks

      - name: Gitleaks — secret scanning
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: Checkov — Terraform static analysis
        uses: bridgecrewio/checkov-action@v12
        with:
          directory: terraform/
          framework: terraform
          output_format: sarif
          output_file_path: checkov-results.sarif
          soft_fail: false
          # Skip checks that are intentionally accepted risks (document reasons)
          skip_check: "CKV_AZURE_13"  # Example: Function App auth not applicable

      - name: Upload Checkov SARIF to GitHub Security
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: checkov-results.sarif

  # ------------------------------------------------------------------
  # JOB 3: Terraform plan (runs on PR and push to main)
  # ------------------------------------------------------------------
  terraform-plan:
    name: Terraform Plan
    runs-on: ubuntu-latest
    needs: [build-test, security-gates]

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Login to Azure (OIDC — no stored secrets)
        uses: azure/login@v2
        with:
          client-id:       ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id:       ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Setup Terraform ${{ env.TF_VERSION }}
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Terraform Init
        working-directory: ${{ env.TF_WORKING_DIR }}
        env:
          ARM_USE_OIDC:        true
          ARM_CLIENT_ID:       ${{ secrets.AZURE_CLIENT_ID }}
          ARM_TENANT_ID:       ${{ secrets.AZURE_TENANT_ID }}
          ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
        run: |
          terraform init \
            -backend-config="resource_group_name=${{ secrets.TF_STATE_RG }}" \
            -backend-config="storage_account_name=${{ secrets.TF_STATE_SA }}" \
            -backend-config="container_name=tfstate" \
            -backend-config="key=dev.terraform.tfstate"

      - name: Terraform Format Check
        working-directory: ${{ env.TF_WORKING_DIR }}
        run: terraform fmt -check -recursive

      - name: Terraform Validate
        working-directory: ${{ env.TF_WORKING_DIR }}
        run: terraform validate

      - name: Terraform Plan
        working-directory: ${{ env.TF_WORKING_DIR }}
        env:
          ARM_USE_OIDC:        true
          ARM_CLIENT_ID:       ${{ secrets.AZURE_CLIENT_ID }}
          ARM_TENANT_ID:       ${{ secrets.AZURE_TENANT_ID }}
          ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
          TF_VAR_sql_admin_login:    ${{ secrets.SQL_ADMIN_LOGIN }}
          TF_VAR_sql_admin_password: ${{ secrets.SQL_ADMIN_PASSWORD }}
        run: |
          terraform plan \
            -var-file="terraform.tfvars" \
            -out=tfplan \
            -detailed-exitcode

      - name: Upload Terraform plan
        uses: actions/upload-artifact@v4
        with:
          name: tfplan
          path: ${{ env.TF_WORKING_DIR }}/tfplan
          retention-days: 1

  # ------------------------------------------------------------------
  # JOB 4: Terraform apply — only on push to main, requires approval
  # ------------------------------------------------------------------
  terraform-apply:
    name: Terraform Apply
    runs-on: ubuntu-latest
    needs: terraform-plan
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    environment: dev-deploy   # Configure required reviewers in GitHub Environments settings

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Login to Azure (OIDC)
        uses: azure/login@v2
        with:
          client-id:       ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id:       ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Setup Terraform ${{ env.TF_VERSION }}
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Download Terraform plan
        uses: actions/download-artifact@v4
        with:
          name: tfplan
          path: ${{ env.TF_WORKING_DIR }}

      - name: Terraform Init
        working-directory: ${{ env.TF_WORKING_DIR }}
        env:
          ARM_USE_OIDC:        true
          ARM_CLIENT_ID:       ${{ secrets.AZURE_CLIENT_ID }}
          ARM_TENANT_ID:       ${{ secrets.AZURE_TENANT_ID }}
          ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
        run: |
          terraform init \
            -backend-config="resource_group_name=${{ secrets.TF_STATE_RG }}" \
            -backend-config="storage_account_name=${{ secrets.TF_STATE_SA }}" \
            -backend-config="container_name=tfstate" \
            -backend-config="key=dev.terraform.tfstate"

      - name: Terraform Apply
        working-directory: ${{ env.TF_WORKING_DIR }}
        env:
          ARM_USE_OIDC:        true
          ARM_CLIENT_ID:       ${{ secrets.AZURE_CLIENT_ID }}
          ARM_TENANT_ID:       ${{ secrets.AZURE_TENANT_ID }}
          ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
          TF_VAR_sql_admin_login:    ${{ secrets.SQL_ADMIN_LOGIN }}
          TF_VAR_sql_admin_password: ${{ secrets.SQL_ADMIN_PASSWORD }}
        run: terraform apply -auto-approve tfplan

  # ------------------------------------------------------------------
  # JOB 5: Deploy app to Azure App Service
  # ------------------------------------------------------------------
  deploy:
    name: Deploy to Azure App Service
    runs-on: ubuntu-latest
    needs: terraform-apply
    environment: dev-deploy

    steps:
      - name: Download build artifact
        uses: actions/download-artifact@v4
        with:
          name: app-package

      - name: Login to Azure (OIDC)
        uses: azure/login@v2
        with:
          client-id:       ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id:       ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Deploy to App Service
        uses: azure/webapps-deploy@v3
        with:
          app-name: ${{ vars.AZURE_WEBAPP_NAME }}
          package:  ${{ env.ARTIFACT_NAME }}

      - name: Post-deploy smoke test
        run: |
          APP_URL="https://${{ vars.AZURE_WEBAPP_HOSTNAME }}"
          echo "Smoke testing $APP_URL/health"
          for i in {1..5}; do
            STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$APP_URL/health")
            if [ "$STATUS" = "200" ]; then
              echo "Health check passed (HTTP $STATUS)"
              exit 0
            fi
            echo "Attempt $i: HTTP $STATUS — retrying in 10s..."
            sleep 10
          done
          echo "Smoke test failed after 5 attempts"
          exit 1
```

---

## 6. Security Implementation Notes

### Why OIDC over client secrets in GitHub Actions?
Client secrets are static, long-lived credentials that must be manually rotated. Workload Identity Federation issues short-lived tokens scoped to a specific repository and branch — no secret ever touches GitHub or your pipeline environment.

**Setup steps:**
```bash
# Create Service Principal
az ad sp create-for-rbac --name "sp-netwrix-github-actions" --skip-assignment --output json

# Add federated credential for the main branch
az ad app federated-credential create \
  --id <app-object-id> \
  --parameters '{
    "name": "github-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:<org>/<repo>:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# Assign role to resource group
az role assignment create \
  --assignee <sp-client-id> \
  --role Contributor \
  --scope /subscriptions/<sub-id>/resourceGroups/rg-netwrix-dev
```

### Key Vault Reference syntax for App Settings
```
@Microsoft.KeyVault(SecretUri=https://kv-netwrix-dev.vault.azure.net/secrets/db-connection-string/)
```
The App Service managed identity must have the **Key Vault Secrets User** role on the vault. Terraform handles this assignment in the key_vault module.

### SQL — Managed Identity authentication (no password in connection string)
In `appsettings.json` (or via App Settings Key Vault reference):
```json
"ConnectionStrings": {
  "DefaultConnection": "Server=tcp:sql-netwrix-dev.database.windows.net;Database=sqldb-netwrix-dev;Authentication=Active Directory Default;"
}
```
The `Authentication=Active Directory Default` driver uses the hosting environment's managed identity automatically — no username/password.

Add the MI as a contained database user after first deployment:
```sql
CREATE USER [app-netwrix-dev] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [app-netwrix-dev];
ALTER ROLE db_datawriter ADD MEMBER [app-netwrix-dev];
```

---

## 7. Monitoring & Observability

### Key Log Analytics queries

**WAF blocks in last 24 hours:**
```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.NETWORK"
| where Category == "ApplicationGatewayFirewallLog"
| where action_s == "Blocked"
| summarize count() by bin(TimeGenerated, 1h), ruleId_s
| order by TimeGenerated desc
```

**App Service 5xx errors:**
```kusto
AppServiceHTTPLogs
| where ScStatus >= 500
| summarize count() by bin(TimeGenerated, 5m), CsUriStem
| order by TimeGenerated desc
```

**Application map & dependencies:** Available out-of-the-box in Application Insights — navigate to your App Insights resource → Application Map.

### Availability tests
Create in Application Insights → Availability to test the `/health` endpoint every 5 minutes from multiple regions. Alert on > 2 consecutive failures.

---

## 8. Presentation Talking Points

When presenting to Netwrix, be ready to address:

1. **"Why App Service over VMs or AKS?"**
   — Managed PaaS reduces operational burden; built-in deployment slots allow zero-downtime swaps; native .NET runtime support. AKS is the right answer when you need multi-tenant workloads, fine-grained resource control, or advanced networking — out of scope here.

2. **"How do you handle secrets rotation?"**
   — Key Vault secret versioning; update the secret version, no app restart required (versionless URI). For SQL admin password — use `random_password` in Terraform and store it in Key Vault; production workloads should use MI-only auth and disable SQL auth entirely.

3. **"What would you do differently in production?"**
   — Private endpoint for App Service (inbound, not just outbound) to eliminate the public endpoint entirely; ASE v3 for complete VNet isolation; Front Door in front of App Gateway for global routing and DDoS protection; separate subscriptions per environment (landing zone pattern).

4. **"How does Terraform state get protected?"**
   — Azure Storage with GRS, blob versioning, and a 30-day delete retention policy. State locking is handled natively by the azurerm backend using Azure Blob Storage leases. The storage account itself should be in a separate subscription or at minimum a separate resource group with stricter RBAC.

5. **"What security gates are in the pipeline?"**
   — Gitleaks prevents secret commits reaching the repo. Checkov fails the pipeline if Terraform code violates security policies (e.g., storage account allows public blob access, SQL firewall open to 0.0.0.0). The manual approval gate on the `dev-deploy` environment prevents automated infrastructure changes without human sign-off.
