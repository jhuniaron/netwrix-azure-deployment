# Netwrix Azure Deployment — Complete System Diagram

> View this file in VS Code with the **Markdown Preview Mermaid Support** extension,
> or push to GitHub and view the file there — GitHub renders Mermaid natively.

```mermaid
flowchart TD

    %% ══════════════════════════════════════════════════════════════
    %% EXTERNAL ACTORS
    %% ══════════════════════════════════════════════════════════════

    USER["🌐 Internet<br/>Users + Bots + Scanners"]
    RUNNER["⚙️ GitHub Actions Runner<br/>ubuntu-latest (GitHub-hosted)<br/>Production gap: should be self-hosted in VNet"]

    %% ══════════════════════════════════════════════════════════════
    %% GITHUB
    %% ══════════════════════════════════════════════════════════════

    subgraph GH["GitHub — jhuniaron/netwrix-azure-deployment"]
        WF["deploy.yml — 5-job pipeline<br/>Trigger: push to main or PR<br/>Jobs: Build+Test → Security Gates → TF Plan → TF Apply → Deploy"]
        GHV["Variables (not secrets — just IDs)<br/>AZURE_CLIENT_ID = e9bba11f-...<br/>AZURE_TENANT_ID<br/>AZURE_SUBSCRIPTION_ID = 69a76f8c-...<br/>AZURE_APPGW_IP = 20.92.246.30<br/>📍 Settings → Secrets and variables → Actions → Variables tab"]
        GHE["Environment: dev-deploy<br/>Required reviewer: jhuniaron<br/>Gates Jobs 4 and 5 (Apply + Deploy)<br/>📍 Settings → Environments → dev-deploy"]
    end

    %% ══════════════════════════════════════════════════════════════
    %% MICROSOFT ENTRA ID (Azure AD)
    %% ══════════════════════════════════════════════════════════════

    subgraph ENTRA["Microsoft Entra ID (Azure AD)"]
        SP["Service Principal: sp-netwrix-github-actions<br/>AppID: e9bba11f-5d1a-4007-adce-0053833ee224<br/>Enterprise OID: 9e17a4f1-f7e0-4725-a815-7dcb19cca4f0<br/>Roles: Contributor + User Access Administrator<br/>Scope: /subscriptions/69a76f8c-...<br/>📍 AAD → App registrations → sp-netwrix-github-actions"]
        FC1["Federated Credential 1: github-main<br/>Subject: repo:jhuniaron/netwrix-azure-deployment:ref:refs/heads/main<br/>Used by: Jobs 1-3 (no environment — branch context)<br/>📍 App reg → Certificates and secrets → Federated credentials"]
        FC2["Federated Credential 2: github-actions-dev-deploy-env<br/>Subject: repo:jhuniaron/netwrix-azure-deployment:environment:dev-deploy<br/>Used by: Jobs 4-5 (inside dev-deploy environment)<br/>📍 App reg → Certificates and secrets → Federated credentials"]
        SP --- FC1
        SP --- FC2
    end

    %% ══════════════════════════════════════════════════════════════
    %% TERRAFORM STATE
    %% ══════════════════════════════════════════════════════════════

    subgraph TFSA["Storage Account: tfstateiaron30<br/>📍 Storage accounts → tfstateiaron30"]
        TFBLOB["Container: tfstate<br/>Blob: netwrix-dev.terraform.tfstate<br/>Auth: AAD only — no storage access keys<br/>ARM_USE_AZUREAD=true + use_azuread_auth=true<br/>SP role: Storage Blob Contributor<br/>Locking: Azure Blob lease (prevents concurrent applies)<br/>📍 tfstateiaron30 → Containers → tfstate"]
    end

    %% ══════════════════════════════════════════════════════════════
    %% AZURE VIRTUAL NETWORK
    %% ══════════════════════════════════════════════════════════════

    subgraph VNET["Virtual Network: vnet-netwrix-dev — 10.0.0.0/16<br/>📍 Virtual networks → vnet-netwrix-dev"]

        subgraph GWSUB["snet-gateway — 10.0.0.0/26 (dedicated — App GW requirement, min /26 for autoscale)<br/>📍 VNet → Subnets → snet-gateway"]
            NSGGW["NSG: nsg-gateway-netwrix-dev<br/>✅ Inbound 100: Allow 443 from Internet<br/>✅ Inbound 110: Allow 80 from Internet (HTTP→HTTPS redirect)<br/>✅ Inbound 120: Allow 65200-65535 from GatewayManager (Azure health probes — MUST exist)<br/>❌ Inbound 65500: DenyAllInbound<br/>📍 Network security groups → nsg-gateway-netwrix-dev"]
            PIP["Public IP: pip-appgw-netwrix-dev<br/>Current IP: 20.92.246.30<br/>Allocation: Dynamic (production gap — should be Static)<br/>📍 Public IP addresses → pip-appgw-netwrix-dev"]
            AGW["Application Gateway: appgw-netwrix-dev<br/>SKU: WAF_v2 (autoscales capacity units min 1 max 10)<br/>Listeners: HTTP:80 (redirect rule) + HTTPS:443 (routing rule)<br/>Backend pool: app-netwrix-dev.azurewebsites.net (hostname)<br/>Backend settings: HTTPS port 443 — end-to-end TLS<br/>Health probe: probe-netwrix-dev → GET /health every 30s<br/>TLS cert: appgw-tls from Key Vault via user-assigned MI<br/>📍 Application gateways → appgw-netwrix-dev"]
            WAFP["WAF Policy: wafpol-netwrix-dev<br/>Policy state: Enabled | Mode: Prevention (blocks — not just logs)<br/>Managed ruleset: OWASP CRS 3.2 (covers OWASP Top 10)<br/>Bot Manager rules: enabled<br/>Custom rule: BlockKnownScanners (matches User-Agent header)<br/>Linked to: appgw-netwrix-dev (Associations: 1)<br/>📍 Web Application Firewall policies → wafpol-netwrix-dev"]
        end

        subgraph APPSUB["snet-app — 10.0.1.0/24 (larger for App Service scale-out)<br/>📍 VNet → Subnets → snet-app"]
            NSGAPP["NSG: nsg-app-netwrix-dev<br/>❌ Inbound 1000: deny-internet-inbound (custom rule — blocks direct internet access)<br/>Inbound 65000: AllowVnetInBound (Azure default — allows App GW)<br/>📍 Network security groups → nsg-app-netwrix-dev"]
            AS["App Service: app-netwrix-dev<br/>Runtime: Linux / .NET 10 / B2 SKU<br/>Slots: production + staging (zero-downtime swap)<br/>Access restriction: ONLY snet-gateway CIDR 10.0.0.0/26<br/>Direct *.azurewebsites.net → 403 Forbidden<br/>VNet Integration: outbound traffic via snet-app<br/>Deployment: zip deploy to staging slot → smoke test → swap to production<br/>📍 App Services → app-netwrix-dev"]
            SAMI["System-Assigned Managed Identity<br/>Principal ID: 7d85284e-b73a-40a5-a790-d3cae559b61b<br/>Azure AD identity for this specific App Service instance<br/>No password or secret — Azure AD issues tokens automatically<br/>📍 App Service → Identity → System assigned (Status: On)"]
        end

        subgraph DATASUB["snet-data — 10.0.2.0/28 (small — only 1 PE needs 1 IP)<br/>📍 VNet → Subnets → snet-data"]
            PESQL["Private Endpoint: pe-sql-netwrix-dev<br/>Target: sql-netwrix-dev (SQL Server)<br/>NIC assigned private IP: 10.0.2.x<br/>SQL has zero public IP — only reachable via this PE<br/>📍 Private endpoints → pe-sql-netwrix-dev"]
        end

        subgraph PESUB["snet-pe — 10.0.3.0/28 (small — only 1 PE needs 1 IP)<br/>📍 VNet → Subnets → snet-pe"]
            PEKV["Private Endpoint: pe-kv-netwrix-dev<br/>Target: kv-netwrix-dev (Key Vault)<br/>NIC assigned private IP: 10.0.3.x<br/>KV reachable on 443 via this PE from snet-app<br/>📍 Private endpoints → pe-kv-netwrix-dev"]
        end

    end

    %% ══════════════════════════════════════════════════════════════
    %% USER-ASSIGNED MI (outside modules — breaks circular dependency)
    %% ══════════════════════════════════════════════════════════════

    UAMI["User-Assigned MI: id-appgw-netwrix-dev<br/>WHY in root main.tf and not in waf module:<br/>  waf module needs KV cert secret ID (from key_vault module)<br/>  key_vault module needs this identity's principal ID (from waf module)<br/>  → circular dependency: A needs B, B needs A<br/>  Solution: create identity in root, pass to BOTH modules as input<br/>📍 Managed Identities → id-appgw-netwrix-dev"]

    %% ══════════════════════════════════════════════════════════════
    %% PRIVATE DNS ZONES
    %% ══════════════════════════════════════════════════════════════

    subgraph PDNS["Private DNS Zones — linked to vnet-netwrix-dev<br/>📍 Private DNS zones"]
        DNSSQL["privatelink.database.windows.net<br/>Record: sql-netwrix-dev.database.windows.net → 10.0.2.x<br/>Overrides public DNS — SQL resolves to private IP inside VNet"]
        DNSKV["privatelink.vaultcore.azure.net<br/>Record: kv-netwrix-dev.vault.azure.net → 10.0.3.x<br/>Overrides public DNS — KV resolves to private IP inside VNet"]
    end

    %% ══════════════════════════════════════════════════════════════
    %% KEY VAULT
    %% ══════════════════════════════════════════════════════════════

    subgraph KV["Key Vault: kv-netwrix-dev<br/>Auth model: RBAC (not legacy Access Policies)<br/>Soft-delete: 90 days + Purge protection: true<br/>Public access: true (GitHub runner needs it for secret injection)<br/>App Service access: via Private Endpoint 10.0.3.x<br/>📍 Key vaults → kv-netwrix-dev"]
        KVCERT["Certificate: appgw-tls<br/>Self-signed (production gap — replace with Let's Encrypt or CA cert)<br/>Used by App Gateway for TLS termination<br/>📍 KV → Certificates → appgw-tls"]
        KVS1["Secret: db-connection-string<br/>Value: AAD passwordless SQL connection string<br/>Injected into App Service via KV Reference<br/>📍 KV → Secrets → db-connection-string"]
        KVS2["Secret: appinsights-connection-string<br/>Value: InstrumentationKey=...;IngestionEndpoint=...<br/>Injected into App Service via KV Reference<br/>📍 KV → Secrets → appinsights-connection-string"]
    end

    %% ══════════════════════════════════════════════════════════════
    %% SQL SERVER
    %% ══════════════════════════════════════════════════════════════

    subgraph SQLSRV["SQL Server: sql-netwrix-dev<br/>Public network access: Disabled (no public endpoint at all)<br/>AAD admin configured — SQL password auth still possible<br/>📍 SQL servers → sql-netwrix-dev"]
        SQLDB["Database: sqldb-netwrix-dev<br/>Tier: Serverless GP_S_Gen5_1<br/>vCores: 0.5–4 (auto-scales), auto-pause when idle (cost saving)<br/>TDE: enabled by default<br/>App access: Contained DB user mapped to App Service MI principal<br/>No SQL password — MI authenticates via Azure AD token"]
        DEFSQL["Microsoft Defender for SQL<br/>Threat detection: SQL injection patterns, brute force, unusual access<br/>Vulnerability assessment: scans schema and config for weaknesses<br/>Alerts: sent to configured alert_email via Defender for Cloud<br/>📍 SQL server → Microsoft Defender for Cloud"]
    end

    %% ══════════════════════════════════════════════════════════════
    %% MONITORING
    %% ══════════════════════════════════════════════════════════════

    subgraph MON["Monitoring — created last (depends on all other modules for resource IDs)"]
        LAW["Log Analytics Workspace: law-netwrix-dev<br/>SKU: PerGB2018 | Retention: 90 days<br/>Central log sink — all Azure services ship here<br/>Query: Kusto KQL — correlate across all resources<br/>📍 Log Analytics workspaces → law-netwrix-dev → Logs"]
        APPI["Application Insights: appi-netwrix-dev<br/>Type: workspace-based (linked to law-netwrix-dev)<br/>SDK: builder.Services.AddApplicationInsightsTelemetry()<br/>Auto-collects: HTTP requests, exceptions, SQL dep calls, response times<br/>Conn string injected from KV Reference at runtime<br/>📍 Application Insights → appi-netwrix-dev → Investigate → Failures / Live Metrics"]
        ALRT["Metric Alert: alert-http5xx-netwrix-dev<br/>Condition: Http5xx count > 10 in 5-minute window<br/>Frequency: check every 1 minute<br/>Action: ag-ops-netwrix-dev → email ops<br/>📍 Monitor → Alerts"]
        DGW["Diagnostic Setting: diag-appgw-netwrix-dev<br/>Target: appgw-netwrix-dev<br/>Logs: ApplicationGatewayAccessLog + ApplicationGatewayFirewallLog<br/>Metrics: AllMetrics<br/>Destination: law-netwrix-dev<br/>📍 App GW → Diagnostic settings"]
        DAS["Diagnostic Setting: diag-app-netwrix-dev<br/>Target: app-netwrix-dev<br/>Logs: AppServiceHTTPLogs + AppServiceConsoleLogs + AppServiceAppLogs<br/>Metrics: AllMetrics<br/>Destination: law-netwrix-dev<br/>📍 App Service → Diagnostic settings"]
    end

    %% ══════════════════════════════════════════════════════════════
    %% CONNECTIONS — TRAFFIC FLOW
    %% ══════════════════════════════════════════════════════════════

    USER -->|"HTTPS 443 or HTTP 80<br/>DNS A record → public IP 20.92.246.30"| PIP
    PIP --> AGW
    AGW <-->|"WAF policy linked<br/>all traffic inspected before forwarding<br/>📍 App GW → Web application firewall"| WAFP
    AGW -->|"HTTPS 443 end-to-end TLS (not SSL offload)<br/>Backend pool: app-netwrix-dev.azurewebsites.net<br/>📍 App GW → Backend pools + Backend settings + Health probes"| AS

    %% ══════════════════════════════════════════════════════════════
    %% CONNECTIONS — APP GW TLS CERT FROM KEY VAULT
    %% ══════════════════════════════════════════════════════════════

    AGW -->|"reads TLS cert at deploy time<br/>using user-assigned MI identity<br/>📍 App GW → Listeners → HTTPS listener → cert source"| UAMI
    UAMI -->|"RBAC: Key Vault Certificates User<br/>📍 KV → Access control IAM → Role assignments"| KVCERT

    %% ══════════════════════════════════════════════════════════════
    %% CONNECTIONS — ACCESS RESTRICTION (what direct access looks like)
    %% ══════════════════════════════════════════════════════════════

    USER -.->|"direct *.azurewebsites.net = 403 Forbidden<br/>access restriction: only 10.0.0.0/26 allowed<br/>📍 App Service → Networking → Access restriction"| AS

    %% ══════════════════════════════════════════════════════════════
    %% CONNECTIONS — APP SERVICE → KEY VAULT (secrets)
    %% ══════════════════════════════════════════════════════════════

    AS -->|"KV References in App Settings at runtime:<br/>APPLICATIONINSIGHTS_CONNECTION_STRING =<br/>  @Microsoft.KeyVault(SecretUri=https://kv-.../secrets/appinsights-...)<br/>ConnectionStrings__DefaultConnection =<br/>  @Microsoft.KeyVault(SecretUri=https://kv-.../secrets/db-...)<br/>Azure resolves to real values using MI token — never stored in plain text<br/>📍 App Service → Environment variables"| KVS1
    AS --> KVS2
    SAMI -->|"RBAC: Key Vault Secrets User (read only — not write/delete)<br/>📍 KV → Access control IAM → Role assignments"| KV
    AS -->|"outbound via VNet Integration → snet-app → snet-pe"| PEKV
    PEKV --> DNSKV
    DNSKV -->|"DNS overrides public resolution → 10.0.3.x<br/>traffic never leaves VNet backbone"| KV

    %% ══════════════════════════════════════════════════════════════
    %% CONNECTIONS — APP SERVICE → SQL (database)
    %% ══════════════════════════════════════════════════════════════

    AS -->|"outbound via VNet Integration → snet-app → snet-data<br/>AAD token auth — no SQL password anywhere<br/>📍 App Service → Networking → VNet integration"| PESQL
    PESQL --> DNSSQL
    DNSSQL -->|"DNS overrides public resolution → 10.0.2.x<br/>traffic never leaves VNet backbone"| SQLSRV
    SAMI -->|"Azure AD token → Contained DB user<br/>mapped to principal 7d85284e-...<br/>📍 SQL server → Microsoft Entra ID"| SQLDB

    %% ══════════════════════════════════════════════════════════════
    %% CONNECTIONS — APP SERVICE → APP INSIGHTS
    %% ══════════════════════════════════════════════════════════════

    AS -->|"SDK auto-collects: HTTP request traces, exceptions,<br/>SQL dependency calls, response times, availability<br/>Connection string resolved from KV Reference at runtime"| APPI
    APPI --> LAW
    ALRT --> LAW

    %% ══════════════════════════════════════════════════════════════
    %% CONNECTIONS — DIAGNOSTIC SETTINGS → LOG ANALYTICS
    %% ══════════════════════════════════════════════════════════════

    AGW -->|"📍 App GW → Diagnostic settings"| DGW
    DGW --> LAW
    AS -->|"📍 App Service → Diagnostic settings"| DAS
    DAS --> LAW

    %% ══════════════════════════════════════════════════════════════
    %% CONNECTIONS — GITHUB ACTIONS OIDC AUTH
    %% ══════════════════════════════════════════════════════════════

    RUNNER -->|"Step 1: GitHub runtime generates short-lived OIDC JWT<br/>Step 2: azure/login@v2 sends JWT + client-id to Azure AD<br/>Step 3: Azure AD validates subject claim against federated credential<br/>Step 4: If matched, issues short-lived Azure access token (~1hr)<br/>Step 5: All az CLI + Terraform commands use this token<br/>NO client secret stored anywhere<br/>📍 AAD → App registrations → Federated credentials<br/>📍 Workflow: azure/login@v2 with client-id, tenant-id, subscription-id"| SP
    SP -->|"short-lived access token returned to runner"| RUNNER

    %% ══════════════════════════════════════════════════════════════
    %% CONNECTIONS — GITHUB ACTIONS → TERRAFORM STATE
    %% ══════════════════════════════════════════════════════════════

    RUNNER -->|"terraform init: downloads state from blob<br/>terraform plan: reads state + calls Azure API → diff<br/>terraform apply: updates state after resource changes<br/>SP role: Storage Blob Contributor on tfstateiaron30<br/>📍 Storage account → Containers → tfstate → netwrix-dev.terraform.tfstate"| TFBLOB

    %% ══════════════════════════════════════════════════════════════
    %% CONNECTIONS — GITHUB ACTIONS → AZURE RESOURCES
    %% ══════════════════════════════════════════════════════════════

    RUNNER -->|"terraform apply creates/modifies all Azure resources<br/>SP: Contributor (create resources)<br/>SP: User Access Administrator (assign RBAC roles)<br/>📍 Subscription → Access control IAM → Role assignments"| AGW

    %% ══════════════════════════════════════════════════════════════
    %% CONNECTIONS — PIPELINE GATE
    %% ══════════════════════════════════════════════════════════════

    GHE -->|"manual approval required before Job 4 (TF Apply) and Job 5 (Deploy)<br/>Reviewer reads TF Plan output then approves<br/>📍 GitHub Actions → run in progress → Review deployments"| WF
    WF --> RUNNER

    %% ══════════════════════════════════════════════════════════════
    %% CONNECTIONS — NSG PROTECTION
    %% ══════════════════════════════════════════════════════════════

    NSGGW -. "guards App Gateway subnet" .-> AGW
    NSGAPP -. "guards App Service subnet" .-> AS

    %% ══════════════════════════════════════════════════════════════
    %% CONNECTIONS — PRIVATE DNS LINKED TO VNET
    %% ══════════════════════════════════════════════════════════════

    PDNS -.->|"virtual network links → vnet-netwrix-dev<br/>overrides public Azure DNS for privatelink zones<br/>📍 Private DNS zones → Virtual network links"| PESQL
```

---

## Production Gaps (what would change for real production)

| # | Gap | Current State | Production Fix |
|---|---|---|---|
| 1 | GitHub runner | GitHub-hosted (public IP) → forces KV + App Service public access | Self-hosted runner inside VNet → eliminates all public access exceptions |
| 2 | TLS certificate | Self-signed (`appgw-tls`) → browsers show security warning | CA-issued cert via Let's Encrypt + KV auto-renewal policy |
| 3 | Public IP allocation | Dynamic → changes on every redeploy (Issue #21) | Static allocation + custom domain DNS A record |
| 4 | Multi-region / DR | Single region (australiaeast) | Paired region + geo-replicated SQL + Azure Front Door for failover |
| 5 | Client secret | One leftover on SP (not used) | Delete it — no reason for it to exist alongside OIDC |
| 6 | SQL monitoring alerts | No metric alerts on SQL CPU/DTU | Add `azurerm_monitor_metric_alert` scoped to SQL resource |
| 7 | WAF coverage | `/containers/json` Docker API probes reaching app (returns 404) | Add custom WAF rule to block at gateway before reaching app |

## Terraform Module Dependency Order

```
networking (first — all others need its outputs)
    ↓
database ──→ app_service ──→ key_vault
                                 ↓
                              waf (needs cert from KV, UAMI from root)
                                 ↓
                           monitoring (last — needs App GW ID + App Service ID)
```

## OIDC Token Flow (per pipeline run)

```
push to main
    → GitHub generates JWT: { sub: "repo:jhuniaron/...:ref:refs/heads/main", exp: now+5min }
    → azure/login@v2 sends JWT to: https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token
    → Azure AD checks: does SP e9bba11f have a federated credential matching this subject?
    → Yes (github-main) → issues Azure access token (scope: https://management.azure.com/)
    → Token stored in runner env → all az + terraform commands use it
    → Token expires in ~1hr → nothing to rotate, nothing to leak
```
