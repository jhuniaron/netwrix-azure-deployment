# Azure Terraform .NET Deployment — Completion Checklist

> **Project:** Netwrix Technical Assessment — Azure Terraform-Based .NET 10 Deployment
> Track progress phase by phase. Each checked item is a concrete deliverable.

---

## Phase 0 — Environment Setup

- [x] Azure subscription confirmed and accessible — `Azure subscription 1` (`69a76f8c-1ff3-4ff8-9ffe-4b77b1d0273e`), Tenant `f8b9e996-e47a-4302-bed1-d6cda47b9368`
- [x] Azure CLI installed and authenticated (`az login`) — v2.85.0
- [x] Terraform ≥ 1.9 installed and verified (`terraform -version`) — v1.14.8
- [x] .NET 10 SDK installed (`dotnet --version`) — v10.0.201
- [x] Git and GitHub account configured — v2.53.0 (Jhun Fedelino / jhuniaron.fedelino@gmail.com)
- [x] GitHub repository created (public or private) — `https://github.com/jhuniaron/netwrix-azure-deployment`
- [x] GitHub Actions enabled on repository
- [x] Service Principal created for OIDC (no client secret stored) — `sp-netwrix-github-actions` (`e9bba11f-5d1a-4007-adce-0053833ee224`)
- [x] Federated credential configured for `main` branch
- [x] SP assigned **Contributor** + **User Access Administrator** on `rg-netwrix-dev`
- [x] GitHub Secrets populated (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `TF_STATE_RG`, `TF_STATE_SA`, `SQL_ADMIN_LOGIN`, `SQL_ADMIN_PASSWORD`)
- [x] GitHub Variables populated (`AZURE_WEBAPP_NAME`, `AZURE_WEBAPP_HOSTNAME`, `AZURE_RESOURCE_GROUP`)
- [x] GitHub Environment `dev-deploy` created with required reviewers (manual approval gate) — reviewer: `jhuniaron`

---

## Phase 1 — Architecture Document

- [x] Document written covering all six sections:
  - [x] Azure services chosen and why
  - [x] Traffic flow description (or diagram)
  - [x] Network boundaries (subnets, NSG rules)
  - [x] Identity model (OIDC, Managed Identity, RBAC)
  - [x] Key security controls listed
  - [x] Scalability approach described
  - [x] What's missing and what comes next
- [x] Document is 1–2 pages, concise and presentation-ready — `ARCHITECTURE.md`
- [x] Architecture diagram created (ASCII traffic flow diagram in ARCHITECTURE.md)

---

## Phase 2 — Terraform Bootstrap

- [x] Repository folder structure created (`terraform/bootstrap/`, `terraform/environments/dev/`, `terraform/modules/`)
- [x] `terraform/bootstrap/main.tf` written (storage account for remote state) — **SKIPPED: reusing existing**
- [x] Bootstrap run manually: `terraform init && terraform apply` — **SKIPPED: reusing existing**
- [x] Remote state storage account confirmed in Azure portal — `tfstateiaron30` in `terraform-state-rg`, container `tfstate`
- [x] `versions.tf` written with provider constraints and `backend "azurerm"` block
- [x] All 6 modules created and validated — `terraform validate` passes with zero errors/warnings

---

## Phase 3 — Terraform Networking Module

- [x] Module created at `terraform/modules/networking/`
- [x] `main.tf` provisions:
  - [x] Resource Group
  - [x] Virtual Network (`10.0.0.0/16`)
  - [x] `snet-gateway` subnet (`10.0.0.0/26`) — App Gateway
  - [x] `snet-app` subnet (`10.0.1.0/24`) with App Service delegation
  - [x] `snet-data` subnet (`10.0.2.0/28`) for SQL Private Endpoint
  - [x] `snet-pe` subnet (`10.0.3.0/28`) for Key Vault Private Endpoint
  - [x] NSG for gateway subnet (443, 80, 65200-65535 inbound)
  - [x] Private DNS Zone for `privatelink.database.windows.net`
  - [x] Private DNS Zone for `privatelink.vaultcore.azure.net`
  - [x] VNet links for both DNS zones
- [x] `variables.tf` and `outputs.tf` complete
- [x] `terraform validate` passes

---

## Phase 4 — Terraform App Service Module

- [x] Module created at `terraform/modules/app_service/`
- [x] `main.tf` provisions:
  - [x] App Service Plan (Linux, P1v3)
  - [x] Linux Web App (dotnet 10.0)
  - [x] VNet Integration enabled (outbound via `snet-app`)
  - [x] `https_only = true`, FTPS disabled, TLS 1.2 minimum
  - [x] System-Assigned Managed Identity enabled
  - [x] App Settings referencing Key Vault secrets (`@Microsoft.KeyVault(...)`)
  - [x] IP restriction: only `snet-gateway` CIDR allowed inbound
  - [x] Autoscale policy (scale out at 70% CPU, scale in at 30%)
- [x] `variables.tf` and `outputs.tf` complete
- [x] `terraform validate` passes

---

## Phase 5 — Terraform Database Module

- [x] Module created at `terraform/modules/database/`
- [x] `main.tf` provisions:
  - [x] Azure SQL Server (public access disabled, TLS 1.2 min)
  - [x] Azure AD administrator configured
  - [x] Azure SQL Database (GP_S_Gen5_1 Serverless)
  - [x] Defender for SQL (security alert policy + vulnerability assessment)
  - [x] Private Endpoint in `snet-data`
  - [x] Private DNS zone group attached to private endpoint
- [x] `variables.tf` and `outputs.tf` complete
- [x] `terraform validate` passes

---

## Phase 6 — Terraform WAF / Application Gateway Module

- [x] Module created at `terraform/modules/waf/`
- [x] `main.tf` provisions:
  - [x] Standard Public IP (Static)
  - [x] WAF Policy (OWASP CRS 3.2, Prevention mode, Bot Manager rules)
  - [x] Custom WAF rule blocking known scanner User-Agents
  - [x] Application Gateway WAF_v2 with autoscale (min 1, max 10)
  - [x] HTTPS listener with self-signed cert (dev) — Key Vault cert for prod
  - [x] HTTP → HTTPS redirect rule
  - [x] Backend pool targeting App Service hostname
  - [x] Custom health probe (`/health`, HTTPS)
  - [x] Backend HTTP settings (host header preservation)
- [x] `variables.tf` and `outputs.tf` complete
- [x] `terraform validate` passes

---

## Phase 7 — Terraform Key Vault Module

- [x] Module created at `terraform/modules/key_vault/`
- [x] `main.tf` provisions:
  - [x] Key Vault (RBAC mode, purge protection enabled, public access denied)
  - [x] RBAC assignment: App Service MI → **Key Vault Secrets User**
  - [x] RBAC assignment: Terraform SP → **Key Vault Secrets Officer**
  - [x] Secret: `db-connection-string`
  - [x] Secret: `appinsights-connection-string`
  - [x] Private Endpoint in `snet-pe`
  - [x] Private DNS zone group attached to private endpoint
- [x] `variables.tf` and `outputs.tf` complete
- [x] `terraform validate` passes

---

## Phase 8 — Terraform Monitoring Module

- [x] Module created at `terraform/modules/monitoring/`
- [x] `main.tf` provisions:
  - [x] Log Analytics Workspace (90-day retention)
  - [x] Application Insights (workspace-based, web type)
  - [x] Diagnostic setting: App Gateway → Log Analytics
  - [x] Diagnostic setting: App Service → Log Analytics
  - [x] Metric alert: HTTP 5xx > 10 in 5 minutes
  - [x] Action Group with email notification
- [x] `variables.tf` and `outputs.tf` complete
- [x] `terraform validate` passes

---

## Phase 9 — Root Environment Composition

- [x] `terraform/environments/dev/main.tf` written, composing all 6 modules
- [x] `terraform/environments/dev/variables.tf` complete
- [x] `terraform/environments/dev/outputs.tf` exposes key values (app hostname, public IP)
- [x] `terraform/environments/dev/terraform.tfvars` populated (non-sensitive values only)
- [ ] Full `terraform plan` runs without errors — pending pipeline
- [ ] Full `terraform apply` completes successfully — pending pipeline
- [ ] All resources visible and healthy in Azure portal — pending pipeline

---

## Phase 10 — CI/CD Pipeline

- [x] `.github/workflows/deploy.yml` created
- [x] **Job: build-test**
  - [x] `dotnet restore` using `Netwrix.DevOps.Test.sln`
  - [x] `dotnet build` (Release)
  - [x] `dotnet test` with TRX output (scaffolded; activates when test project added)
  - [x] `dotnet publish` to `./publish`
  - [x] Artifact zipped as `Netwrix.DevOps.Test.App.zip`
  - [x] Artifact uploaded to workflow
- [x] **Job: security-gates**
  - [x] Gitleaks secret scan configured
  - [x] Checkov Terraform SAST configured (no high-severity violations)
  - [x] SARIF results uploaded to GitHub Security tab
- [x] **Job: terraform-plan**
  - [x] OIDC login to Azure (no stored secrets)
  - [x] `terraform init` with remote backend
  - [x] `terraform fmt -check` configured
  - [x] `terraform validate` configured
  - [x] `terraform plan` generates and uploads `tfplan` artifact
- [x] **Job: terraform-apply**
  - [x] Only runs on push to `main`
  - [x] Manual approval gate enforced via `dev-deploy` GitHub Environment
  - [x] `terraform apply -auto-approve tfplan` uses saved plan
- [x] **Job: deploy**
  - [x] App artifact deployed via `azure/webapps-deploy@v3`
  - [x] Post-deploy smoke test: 5 retries on `/health`, asserts HTTP 200
- [ ] Full end-to-end pipeline run succeeds (green across all jobs) — pipeline triggered, awaiting run

---

## Phase 11 — Post-Deployment Validation

- [ ] App Service accessible via Application Gateway public IP (HTTPS only)
- [ ] HTTP → HTTPS redirect verified
- [ ] Direct access to App Service URL returns 403 (blocked by IP restriction)
- [ ] WAF blocks a test injection request (e.g., `?id=1 OR 1=1`)
- [ ] App Service reads Key Vault secret correctly (check App Settings resolved values)
- [ ] Application Insights shows live telemetry
- [ ] Log Analytics receives App Gateway firewall logs
- [ ] SQL Database not reachable from public internet (connection refused)
- [ ] Key Vault not reachable from public internet (connection refused)
- [ ] Autoscale rule visible in App Service Plan → Scale Out

---

## Phase 12 — Documentation & Presentation

- [ ] Architecture document finalised (1–2 pages, clean formatting)
- [ ] Architecture diagram exported as image or embedded
- [ ] README.md in repository root summarises the project and deployment steps
- [ ] Pipeline screenshot(s) showing successful green run ready
- [ ] Azure portal screenshots of key resources ready
- [ ] `terraform.tfvars.example` committed (no real values)
- [ ] All sensitive values removed from repository history (verify with Gitleaks)
- [ ] Prepared answers for common interview questions:
  - [ ] Why App Service over AKS/VMs?
  - [ ] How are secrets managed and rotated?
  - [ ] What would production look like differently?
  - [ ] How is Terraform state protected?
  - [ ] What security gates are in the pipeline and why?
- [ ] Presentation walkthrough rehearsed (architecture → code → pipeline → demo)

---

## Quick Reference — Commands

```bash
# Bootstrap remote state (run once)
cd terraform/bootstrap
terraform init && terraform apply

# Init dev environment
cd terraform/environments/dev
terraform init \
  -backend-config="resource_group_name=rg-netwrix-tfstate" \
  -backend-config="storage_account_name=stnetwrixtfstate" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=dev.terraform.tfstate"

# Plan and apply
terraform plan -var-file="terraform.tfvars" -out=tfplan
terraform apply tfplan

# Destroy (dev only — destructive)
terraform destroy -var-file="terraform.tfvars"
```
