# Architecture Proposal
## Azure Terraform-Based .NET 10 Deployment
**Author:** Jhun Fedelino — Netwrix Technical Assessment

---

## 1. Selected Azure Services & Rationale

| Layer | Service | Rationale |
|---|---|---|
| **Compute** | Azure App Service (Linux, P1v3) | Managed PaaS with native .NET 10 runtime support. Built-in deployment slots enable zero-downtime swaps. VNet Integration available from Standard tier upward — no container orchestration overhead for a single application. |
| **Database** | Azure SQL Database (General Purpose Serverless) | Fully managed relational database with native Azure AD authentication, eliminating SQL passwords entirely. Private Endpoint support locks it off from the public internet. Transparent data encryption is on by default. Serverless tier auto-pauses during idle periods to reduce cost. |
| **WAF / Ingress** | Azure Application Gateway v2 — WAF_v2 SKU | Layer-7 load balancing with inline WAF (OWASP CRS 3.2 + Bot Manager rules). SSL offload, HTTP→HTTPS redirect, and custom rules all handled at the gateway. Sits fully inside the VNet. Autoscales capacity units independently of the application. |
| **Networking** | Azure Virtual Network + NSGs + Private Endpoints | Explicit subnet segmentation with NSG rules enforcing least-privilege east-west traffic. Private Endpoints for SQL and Key Vault mean neither service has a routable public IP. |
| **Secrets** | Azure Key Vault (RBAC model) | Single source of truth for connection strings and certificates. App Service Key Vault References inject secrets at runtime — secrets never appear in App Settings in plaintext. Soft-delete and purge protection prevent accidental or malicious deletion. |
| **Identity** | System-Assigned Managed Identity | The App Service authenticates to Key Vault and SQL using its Managed Identity — zero stored credentials anywhere. GitHub Actions authenticates to Azure via Workload Identity Federation (OIDC) — no long-lived secrets in the pipeline. |
| **Logging** | Log Analytics Workspace + Application Insights | Centralised log sink for all Azure services. Application Insights provides distributed tracing, failure analysis, and availability tests. Kusto-based alert rules notify on error spikes. |

---

## 2. Traffic Flow

```
Internet (HTTPS / HTTP)
        │
        ▼
┌─────────────────────────────────────┐
│  Application Gateway  WAF_v2        │  ← OWASP CRS 3.2, Bot Manager, custom rules
│  snet-gateway  10.0.0.0/26          │  ← TLS termination, HTTP→HTTPS redirect
└──────────────────┬──────────────────┘
                   │ HTTPS (host header preserved)
                   ▼
┌─────────────────────────────────────┐
│  Azure App Service  Linux / .NET 10 │  ← Access restricted to gateway subnet only
│  Outbound: VNet Integration         │  ← Key Vault references resolved at startup
└────────────┬────────────────────────┘
             │                  │
             ▼                  ▼
    ┌─────────────────┐  ┌──────────────────┐
    │  Azure SQL DB   │  │  Azure Key Vault  │
    │  Private EP     │  │  Private EP       │
    │  No public access│  │  No public access │
    └─────────────────┘  └──────────────────┘

All diagnostic logs → Log Analytics Workspace → Application Insights / Alerts
```

Direct access to the App Service URL returns **403** — only traffic arriving through the Application Gateway is accepted.

---

## 3. Network Boundaries

| Subnet | CIDR | Purpose | Key NSG Rules |
|---|---|---|---|
| `snet-gateway` | 10.0.0.0/26 | Application Gateway | Inbound: 443 + 80 from Internet; 65200–65535 from GatewayManager (health probes) |
| `snet-app` | 10.0.1.0/24 | App Service VNet Integration (outbound) | Outbound: 443 to data and PE subnets only |
| `snet-data` | 10.0.2.0/28 | SQL Private Endpoint | Inbound: 1433 from `snet-app` only |
| `snet-pe` | 10.0.3.0/28 | Key Vault Private Endpoint | Inbound: 443 from `snet-app` only |

Private DNS Zones for `privatelink.database.windows.net` and `privatelink.vaultcore.azure.net` are linked to the VNet, resolving both services to private IPs — no traffic leaves the VNet backbone.

---

## 4. Identity Model

```
GitHub Actions
  └─ OIDC Federated Credential → Azure AD Service Principal
       └─ Contributer + User Access Administrator (rg-netwrix-dev)

App Service — System-Assigned Managed Identity
  ├─ Key Vault Secrets User (RBAC on Key Vault)
  └─ Contained database user mapped to MI (no SQL password)

Terraform applies role assignments as code — no manual IAM changes
```

No passwords or client secrets are stored in GitHub Secrets, App Settings, or source control.

---

## 5. Key Security Controls

| Control | Implementation |
|---|---|
| WAF | OWASP CRS 3.2 in Prevention mode; Bot Manager rules; custom rule blocking known scanner User-Agents |
| TLS | Minimum TLS 1.2 enforced on App Service and Application Gateway; FTPS disabled |
| Network isolation | Private Endpoints for SQL and Key Vault; App Service IP restriction to gateway subnet only |
| Secret handling | Key Vault References (runtime injection); no plaintext secrets in config or pipeline |
| Credential-free auth | Managed Identity for app-to-service; OIDC for pipeline-to-Azure |
| Threat detection | Microsoft Defender for SQL — threat alerts and vulnerability assessment enabled |
| Secret protection | Key Vault soft-delete (90 days) + purge protection enabled |
| Pipeline gates | Gitleaks (secret scanning on every commit); Checkov (Terraform SAST — fails pipeline on high-severity findings) |
| Manual gate | GitHub Environment `dev-deploy` requires human approval before `terraform apply` or app deployment runs |

---

## 6. Scalability

- **App Service autoscale**: scale out at CPU > 70% sustained 5 minutes (up to 10 instances); scale in at CPU < 30% sustained 10 minutes
- **Application Gateway WAF_v2**: autoscales capacity units independently (min 1, max 10) — no resizing required
- **SQL Serverless**: auto-scales vCores between 0.5 and 4; upgrade path is Hyperscale or Elastic Pool for higher throughput with no schema changes
- **Larger scale path**: migrate compute to **Azure Container Apps** (KEDA-based event-driven autoscale, per-revision traffic splitting) or **AKS** for full container orchestration. Add **Azure Front Door** in front of the Application Gateway for global anycast routing, DDoS protection, and static asset caching.

---

## 7. What's Missing & What Comes Next

| Gap | Priority | Next Step |
|---|---|---|
| Multi-region / disaster recovery | High | Paired region with geo-replicated SQL, Traffic Manager or Front Door for automated failover |
| Full inbound network isolation | Medium | Migrate to App Service Environment v3 — eliminates the public `*.azurewebsites.net` endpoint entirely |
| Container strategy | Medium | Containerise the app, push image to Azure Container Registry, deploy to Container Apps for better density and portability |
| Integration / smoke tests | Medium | Extend pipeline with a post-deploy job that asserts against the live `/health` endpoint and critical API paths |
| Azure Policy | Medium | Enforce tagging standards, allowed regions, and mandatory diagnostic settings across the subscription |
| Cost governance | Low | Azure Cost Management budget alerts; reserved capacity on SQL and App Service once baseline load is known |

---

*Infrastructure managed entirely by Terraform — no manual Azure portal changes required after initial SP setup.*
