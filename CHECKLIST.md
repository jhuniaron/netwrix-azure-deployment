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

- [ ] Document written covering all six sections:
  - [ ] Azure services chosen and why
  - [ ] Traffic flow description (or diagram)
  - [ ] Network boundaries (subnets, NSG rules)
  - [ ] Identity model (OIDC, Managed Identity, RBAC)
  - [ ] Key security controls listed
  - [ ] Scalability approach described
  - [ ] What's missing and what comes next
- [ ] Document is 1–2 pages, concise and presentation-ready
- [ ] Architecture diagram created (Mermaid, Draw.io, or equivalent)

---

## Phase 2 — Terraform Bootstrap

- [ ] Repository folder structure created (`terraform/bootstrap/`, `terraform/environments/dev/`, `terraform/modules/`)
- [x] `terraform/bootstrap/main.tf` written (storage account for remote state) — **SKIPPED: reusing existing**
- [x] Bootstrap run manually: `terraform init && terraform apply` — **SKIPPED: reusing existing**
- [x] Remote state storage account confirmed in Azure portal — `tfstateiaron30` in `terraform-state-rg`, container `tfstate`
- [ ] `versions.tf` written with provider constraints and `backend "azurerm"` block

---

## Phase 3 — Terraform Networking Module

- [ ] Module created at `terraform/modules/networking/`
- [ ] `main.tf` provisions:
  - [ ] Resource Group
  - [ ] Virtual Network (`10.0.0.0/16`)
  - [ ] `snet-gateway` subnet (`10.0.0.0/26`) — App Gateway
  - [ ] `snet-app` subnet (`10.0.1.0/24`) with App Service delegation
  - [ ] `snet-data` subnet (`10.0.2.0/28`) for SQL Private Endpoint
  - [ ] `snet-pe` subnet (`10.0.3.0/28`) for Key Vault Private Endpoint
  - [ ] NSG for gateway subnet (443, 80, 65200-65535 inbound)
  - [ ] Private DNS Zone for `privatelink.database.windows.net`
  - [ ] Private DNS Zone for `privatelink.vaultcore.azure.net`
  - [ ] VNet links for both DNS zones
- [ ] `variables.tf` and `outputs.tf` complete
- [ ] `terraform validate` passes

---

## Phase 4 — Terraform App Service Module

- [ ] Module created at `terraform/modules/app_service/`
- [ ] `main.tf` provisions:
  - [ ] App Service Plan (Linux, P1v3)
  - [ ] Linux Web App (dotnet 10.0)
  - [ ] VNet Integration enabled (outbound via `snet-app`)
  - [ ] `https_only = true`, FTPS disabled, TLS 1.2 minimum
  - [ ] System-Assigned Managed Identity enabled
  - [ ] App Settings referencing Key Vault secrets (`@Microsoft.KeyVault(...)`)
  - [ ] IP restriction: only `snet-gateway` CIDR allowed inbound
  - [ ] Autoscale policy (scale out at 70% CPU, scale in at 30%)
- [ ] `variables.tf` and `outputs.tf` complete
- [ ] `terraform validate` passes

---

## Phase 5 — Terraform Database Module

- [ ] Module created at `terraform/modules/database/`
- [ ] `main.tf` provisions:
  - [ ] Azure SQL Server (public access disabled, TLS 1.2 min)
  - [ ] Azure AD administrator configured
  - [ ] Azure SQL Database (GP_S_Gen5_1 Serverless)
  - [ ] Defender for SQL (security alert policy + vulnerability assessment)
  - [ ] Private Endpoint in `snet-data`
  - [ ] Private DNS zone group attached to private endpoint
- [ ] `variables.tf` and `outputs.tf` complete
- [ ] `terraform validate` passes

---

## Phase 6 — Terraform WAF / Application Gateway Module

- [ ] Module created at `terraform/modules/waf/`
- [ ] `main.tf` provisions:
  - [ ] Standard Public IP (Static)
  - [ ] WAF Policy (OWASP CRS 3.2, Prevention mode, Bot Manager rules)
  - [ ] Custom WAF rule blocking known scanner User-Agents
  - [ ] Application Gateway WAF_v2 with autoscale (min 1, max 10)
  - [ ] HTTPS listener with SSL certificate from Key Vault
  - [ ] HTTP → HTTPS redirect rule
  - [ ] Backend pool targeting App Service hostname
  - [ ] Custom health probe (`/health`, HTTPS)
  - [ ] Backend HTTP settings (host header preservation)
- [ ] `variables.tf` and `outputs.tf` complete
- [ ] `terraform validate` passes

---

## Phase 7 — Terraform Key Vault Module

- [ ] Module created at `terraform/modules/key_vault/`
- [ ] `main.tf` provisions:
  - [ ] Key Vault (RBAC mode, purge protection enabled, public access denied)
  - [ ] RBAC assignment: App Service MI → **Key Vault Secrets User**
  - [ ] RBAC assignment: Terraform SP → **Key Vault Secrets Officer**
  - [ ] Secret: `db-connection-string`
  - [ ] Secret: `appinsights-connection-string`
  - [ ] Private Endpoint in `snet-pe`
  - [ ] Private DNS zone group attached to private endpoint
- [ ] `variables.tf` and `outputs.tf` complete
- [ ] `terraform validate` passes

---

## Phase 8 — Terraform Monitoring Module

- [ ] Module created at `terraform/modules/monitoring/`
- [ ] `main.tf` provisions:
  - [ ] Log Analytics Workspace (90-day retention)
  - [ ] Application Insights (workspace-based, web type)
  - [ ] Diagnostic setting: App Gateway → Log Analytics
  - [ ] Diagnostic setting: App Service → Log Analytics
  - [ ] Metric alert: HTTP 5xx > 10 in 5 minutes
  - [ ] Action Group with email notification
- [ ] `variables.tf` and `outputs.tf` complete
- [ ] `terraform validate` passes

---

## Phase 9 — Root Environment Composition

- [ ] `terraform/environments/dev/main.tf` written, composing all 6 modules
- [ ] `terraform/environments/dev/variables.tf` complete
- [ ] `terraform/environments/dev/outputs.tf` exposes key values (app hostname, public IP)
- [ ] `terraform/environments/dev/terraform.tfvars` populated (non-sensitive values only)
- [ ] Full `terraform plan` runs without errors
- [ ] Full `terraform apply` completes successfully
- [ ] All resources visible and healthy in Azure portal

---

## Phase 10 — CI/CD Pipeline

- [ ] `.github/workflows/deploy.yml` created
- [ ] **Job: build-test**
  - [ ] `dotnet restore` using `Netwrix.DevOps.Test.sln`
  - [ ] `dotnet build` (Release)
  - [ ] `dotnet test` with TRX output
  - [ ] `dotnet publish` to `./publish`
  - [ ] Artifact zipped as `Netwrix.DevOps.Test.App.zip`
  - [ ] Artifact uploaded to workflow
- [ ] **Job: security-gates**
  - [ ] Gitleaks secret scan passes
  - [ ] Checkov Terraform SAST passes (no high-severity violations)
  - [ ] SARIF results uploaded to GitHub Security tab
- [ ] **Job: terraform-plan**
  - [ ] OIDC login to Azure succeeds
  - [ ] `terraform init` with remote backend
  - [ ] `terraform fmt -check` passes
  - [ ] `terraform validate` passes
  - [ ] `terraform plan` generates and uploads `tfplan`
- [ ] **Job: terraform-apply**
  - [ ] Only runs on push to `main`
  - [ ] Manual approval gate enforced via GitHub Environment
  - [ ] `terraform apply` succeeds with saved plan
- [ ] **Job: deploy**
  - [ ] App artifact downloaded and deployed via `azure/webapps-deploy`
  - [ ] Post-deploy smoke test hits `/health` and asserts HTTP 200
- [ ] Full end-to-end pipeline run succeeds (green across all jobs)

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
