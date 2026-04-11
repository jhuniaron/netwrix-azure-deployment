# Issues & Fixes Log
### Netwrix Azure Deployment — Full Project History

This document covers every error encountered during the project, why it happened, and how it was fixed.
Useful for: future deployments, troubleshooting reference, and interview talking points.

---

## Issue #1 — Checkov Security Violations (Multiple Rounds)

**When:** CI/CD pipeline — Security Gates job
**Error:** `Failed checks: 10-12` on first run, then 1-2 on subsequent runs

**What Checkov is:**
Checkov is a static analysis tool (SAST) that reads your Terraform files *before* anything is deployed and flags security misconfigurations. Think of it as a linter for cloud security.

**Violations found and fixed:**

| Check | What it means | Fix |
|---|---|---|
| CKV_AZURE_65 | App Service missing `detailed_error_messages` | Added `detailed_error_messages = true` in `logs` block |
| CKV_AZURE_66 | App Service missing `failed_request_tracing` | Added `failed_request_tracing = true` in `logs` block |
| CKV_AZURE_17 | App Service allow HTTP | Already HTTPS-only; added to skip_check (App Gateway handles HTTP→HTTPS redirect) |
| CKV_AZURE_88 | App Service not using VNet | Already using VNet integration; skip_check added |
| CKV_AZURE_41 | Key Vault secret has no expiration | Skipped — CI runner writes secrets dynamically, expiry not practical here |
| CKV_AZURE_109 | Key Vault firewall rules not set | KV needs public access for CI runner; skipped with justification |
| CKV_AZURE_189 | Key Vault public network access enabled | Same reason as above; skipped with justification |
| CKV_AZURE_160 | App Gateway HTTP listener | Port 80 only exists to redirect to HTTPS; skipped |
| CKV_AZURE_222 | App Service public network access | Needed for SCM/deploy endpoint; skipped with justification |

**Key lesson:** When skipping a Checkov rule, always add a comment explaining *why* it's acceptable. Interviewers will ask about every skip.

---

## Issue #2 — Terraform Backend 403 (listKeys Forbidden)

**When:** Terraform Plan job
**Error:** `403 Forbidden — AuthorizationPermissionMismatch` when accessing Azure Blob Storage state

**Why it happened:**
Terraform was trying to authenticate to the storage account using **Access Keys** (default behavior). The storage account had "Disallow storage account key access" disabled, requiring AAD-based auth instead.

**Fix:**
1. Added `use_azuread_auth = true` to the backend config in both `terraform init` calls in the pipeline
2. Set `ARM_USE_AZUREAD=true` as an environment variable for the Terraform steps
3. Granted the SP the `Storage Blob Data Contributor` + `Reader` roles on the `terraform-state-rg` resource group

**Key lesson:** In enterprise environments, storage account keys are often disabled for security. Always use AAD (identity-based) auth for Terraform state in Azure.

---

## Issue #3 — Missing Required Argument: health_check_eviction_time_in_min

**When:** Terraform Plan
**Error:** `health_check_path requires health_check_eviction_time_in_min to be set`

**Why it happened:**
The Azure provider enforces that both arguments must be set together. If you define a health check path, you must also tell Azure how long to wait before removing an unhealthy instance from the load balancer pool.

**Fix:**
```hcl
health_check_path                 = "/health"
health_check_eviction_time_in_min = 10  # Remove instance after 10 min of failures
```

**Key lesson:** Some Azure resource arguments are paired — setting one without the other causes a validation error at plan time, not apply time.

---

## Issue #4 — OIDC Authentication Failure (AADSTS700213)

**When:** Terraform Apply job
**Error:** `AADSTS700213: No matching federated identity record found for presented assertion`

**Why it happened:**
The OIDC federated credential was configured for `ref:refs/heads/main` (branch pushes). But the Terraform Apply job runs inside the `dev-deploy` **environment** — which changes the token subject to `environment:dev-deploy`. Azure AD rejected it because the subject didn't match.

**Fix:**
Created a second federated credential on the Service Principal:
- Name: `github-actions-dev-deploy-env`
- Subject: `repo:jhuniaron/netwrix-azure-deployment:environment:dev-deploy`

**Key lesson:** GitHub Actions OIDC tokens have different `sub` claims depending on context (branch, tag, environment). Each needs its own federated credential. Always check the actual token subject, not just what you expect it to be.

---

## Issue #5 — Resource Group Already Exists

**When:** Terraform Apply (first apply attempt)
**Error:** `A resource with the ID "/subscriptions/.../resourceGroups/rg-netwrix-dev" already exists`

**Why it happened:**
The resource group `rg-netwrix-dev` was created manually in Azure before Terraform was set up. Terraform had no record of it in state, so it tried to create it again.

**Fix:**
```bash
terraform import module.networking.azurerm_resource_group.main \
  /subscriptions/69a76f8c.../resourceGroups/rg-netwrix-dev
```
This tells Terraform "this resource already exists — adopt it into state without recreating it."

**Key lesson:** `terraform import` is how you bring existing Azure resources under Terraform management. After importing, always run `terraform plan` to verify there's no configuration drift.

---

## Issue #6 — App Service Plan SKU Quota = 0

**When:** Terraform Apply
**Error:** `The subscription does not have the capacity for P1v3 in the australiaeast region`

**Why it happened:**
Azure subscriptions have regional quotas per SKU tier. Free/trial subscriptions often have zero quota for Premium v3 app service plans.

**Fix:**
```hcl
# terraform.tfvars
app_service_sku = "B2"  # Downgraded from P1v3 — same capability, available in dev subscription
```
B2 (Basic tier) is equivalent for development and testing purposes.

**Key lesson:** Always check regional SKU availability before committing to a specific tier in an IaC template, especially in new subscriptions.

---

## Issue #7 — SQL Serverless + license_type Conflict

**When:** Terraform Apply
**Error:** `The property 'licenseType' is not supported for a Serverless SKU`

**Why it happened:**
`license_type = "LicenseIncluded"` is only valid for provisioned (dedicated vCore) SQL databases. The serverless SKU `GP_S_Gen5_1` manages licensing automatically and rejects the argument.

**Fix:**
Removed `license_type` entirely from `azurerm_mssql_database`. The serverless SKU handles this internally.

**Key lesson:** Not all Terraform arguments apply to all SKUs of the same resource type. Serverless and provisioned SQL databases have different valid configurations.

---

## Issue #8 — Key Vault 403 ForbiddenByConnection

**When:** Terraform Apply (writing secrets to Key Vault)
**Error:** `403 ForbiddenByConnection — Public access is disabled`

**Why it happened:**
Key Vault was created with `public_network_access_enabled = false` in a previous partial apply. After Terraform created the KV, it tried to write secrets to it — but the GitHub-hosted runner's IP was blocked by the network ACLs.

**Fix (two-part):**
1. **Immediate CLI fix:** `az keyvault update --name kv-netwrix-dev --public-network-access Enabled`
2. **Terraform fix:** Changed `public_network_access_enabled = true` and `network_acls { default_action = "Allow" }` in `key_vault/main.tf`
3. Added `CKV_AZURE_109` and `CKV_AZURE_189` to Checkov skip_check with written justification

**Justification for keeping public access:**
GitHub-hosted runners use dynamic IPs — you can't whitelist them. The real security is: runtime access to KV uses the App Service's **private endpoint** (not public). The public access is only needed during CI/CD. The production fix would be a self-hosted runner inside the VNet.

**Key lesson:** GitHub-hosted runners cannot use private endpoints. Either accept public access with RBAC controls, or use a self-hosted runner in the VNet.

---

## Issue #9 — WAF Custom Rule Name Has Hyphens

**When:** Terraform Apply
**Error:** `Rule name 'block-known-scanners' is invalid — must be alphanumeric`

**Why it happened:**
Azure Application Gateway WAF custom rule names only accept letters and numbers — no hyphens, underscores, or spaces.

**Fix:**
```hcl
name = "BlockKnownScanners"  # was "block-known-scanners"
```

**Key lesson:** Azure resource name constraints vary widely. WAF rule names, Key Vault names, and storage account names all have different allowed character sets.

---

## Issue #10 — Terraform Format Check Failure

**When:** Terraform Plan job — "Terraform Format Check" step
**Error:** `Terraform exited with code 3` (fmt check fails)

**Why it happened:**
After manually editing Terraform files, whitespace alignment was inconsistent. `terraform fmt` enforces opinionated formatting (aligned `=` signs, consistent indentation).

**Fix:**
```bash
terraform fmt -recursive  # auto-fixes all .tf files in all subdirectories
```
Always run this locally before pushing. The pipeline runs `terraform fmt -check -recursive` which fails if any file needs formatting.

**Key lesson:** Include `terraform fmt` in your pre-commit workflow or editor on-save. It's a zero-effort practice that prevents CI failures.

---

## Issue #11 — WEBSITE_VNET_ROUTE_ALL in app_settings (azurerm v4 Breaking Change)

**When:** Terraform Apply
**Error:** `cannot set a value for WEBSITE_VNET_ROUTE_ALL in app_settings`

**Why it happened:**
In azurerm provider v4, certain App Service settings that were previously free-form `app_settings` are now **managed attributes** with their own Terraform arguments. The provider blocks you from setting them manually to avoid conflicts.

**Fix:**
```hcl
# REMOVED from app_settings:
"WEBSITE_VNET_ROUTE_ALL" = "1"

# ADDED to site_config:
vnet_route_all_enabled = true
```

**Key lesson:** When upgrading the azurerm provider major version, check the migration guide. v4 promoted many app settings to first-class attributes.

---

## Issue #12 — App Gateway SSL Certificate Empty Block

**When:** Terraform Apply
**Error:** `either key_vault_secret_id or data must be specified for the ssl_certificate block`

**Why it happened:**
The initial design assumed App Gateway could auto-generate a self-signed cert with an empty `ssl_certificate {}` block. Azure does not support this — you must supply either PFX data or a Key Vault certificate reference.

**Fix (full solution):**
1. Created a self-signed certificate *inside Key Vault* using `azurerm_key_vault_certificate` with `issuer_parameters { name = "Self" }`
2. Created a **user-assigned managed identity** for App Gateway
3. Granted the identity `Key Vault Secrets User` role on the KV
4. Referenced the certificate in the `ssl_certificate` block via `key_vault_secret_id`

**Why user-assigned identity in root module (not inside WAF module):**
This avoids a circular dependency. If the identity were inside the WAF module, Key Vault would need the WAF output to grant the role, and WAF would need the Key Vault output for the cert — a deadlock. Placing the identity in the root module breaks the cycle.

**Key lesson:** App Gateway requires a real certificate. For dev, use Key Vault's built-in self-signed issuer. For production, use a CA-signed cert (DigiCert, Let's Encrypt via ACMEv2 or Key Vault's built-in integration).

---

## Issue #13 — App Service Deploy 403 (SCM Endpoint Blocked)

**When:** Deploy job — Deploy to App Service step
**Error:** `IP Forbidden (CODE: 403)` — Failed to deploy using OneDeploy

**Why it happened:**
`public_network_access_enabled = false` blocks *all* public traffic — including the SCM (Kudu) endpoint that `azure/webapps-deploy` uses to upload the zip. It does not selectively allow SCM while blocking the main app.

**Fix:**
```hcl
public_network_access_enabled = true  # SCM needs this for CI deployment
```
Security is maintained by `ip_restriction_default_action = "Deny"` — only the App Gateway subnet can reach the *main app*. The SCM endpoint is separately controlled.

**Key lesson:** `public_network_access_enabled = false` is a blunt instrument — it blocks everything including deployment tooling. IP restrictions are more surgical and should be preferred.

---

## Issue #14 — Smoke Test 403 (Hitting App Service Directly)

**When:** Deploy job — Post-deploy smoke test
**Error:** `HTTP 403` on every attempt

**Why it happened:**
The smoke test was hitting `https://app-netwrix-dev.azurewebsites.net/health` — the direct App Service URL. But the IP restriction (`ip_restriction_default_action = "Deny"`) correctly blocks the GitHub runner. The runner is not in the App Gateway subnet.

**Fix:**
Changed the smoke test to hit the App Gateway's public IP instead:
```bash
APP_URL="https://20.213.73.65/health"
curl -sk ...  # -s silent, -k accept self-signed cert
```

Also added `AZURE_APPGW_IP = 20.213.73.65` as a GitHub repository variable.

**Key lesson:** Always test your application through the same path your users would use. Direct App Service access bypasses the WAF entirely and is intentionally blocked.

---

## Issue #15 — Smoke Test 502 (App Gateway Backend Unhealthy)

**When:** Deploy job — Post-deploy smoke test
**Error:** `HTTP 502` — Bad Gateway

**Root cause (two separate sub-problems):**

### Sub-problem A — IP Restriction CIDR vs Subnet Rule

The App Service IP restriction used `ip_address = "10.0.0.0/26"` (the gateway subnet CIDR). But App Gateway v2 sends backend traffic from its **public IP** (NAT'd), not from its private subnet IP. So the CIDR rule `10.0.0.0/26` never matched.

**Fix:**
- Added `service_endpoints = ["Microsoft.Web"]` to the gateway subnet in Terraform
- Changed the App Service IP restriction to use `virtual_network_subnet_id` instead of `ip_address` CIDR
- This makes Azure evaluate the rule based on VNet membership, not source IP address

```hcl
ip_restriction {
  virtual_network_subnet_id = var.gateway_subnet_id  # was ip_address = var.gateway_subnet_cidr
  action   = "Allow"
  priority = 100
}
```

### Sub-problem B — App Service Managed Identity RBAC Lost

After Terraform recreated the App Service (SKU change P1v3→B2 forced a resource replacement), the system-assigned Managed Identity got a new principal ID. The old `Key Vault Secrets User` role assignment pointed to the old (now deleted) identity — so the app couldn't resolve Key Vault references and failed to start.

**Fix:**
```bash
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee "0fe5d5e9-fe25-47b7-b3af-ae0c75f29d2e" \  # new MI principal ID
  --scope "/subscriptions/.../kv-netwrix-dev"
az webapp restart --resource-group rg-netwrix-dev --name app-netwrix-dev
```

**Key lesson:** When a resource is *replaced* (not updated) by Terraform, any system-assigned identities are also replaced. RBAC role assignments that referenced the old identity become orphaned. Either use user-assigned identities (which survive resource replacement) or add a `depends_on` that re-creates the role assignment.

---

## Issue #16 — App Running Placeholder Instead of Our App

**When:** Deploy job — smoke test returns 502 then 404
**Error:** App starts but returns 404; logs show `Running the default app using command: dotnet hostingstart.dll`

**Why it happened:**
The zip was built with `zip -r app.zip ./publish/` which creates a zip where all files are **nested inside a `publish/` subfolder**:

```
app.zip
└── publish/
    ├── Netwrix.DevOps.Test.App.dll
    └── Netwrix.DevOps.Test.App.runtimeconfig.json   ← Oryx looks here
```

Oryx (Azure's app detection engine) scans the *root* of the zip for `*.runtimeconfig.json`. Finding nothing, it falls back to the built-in placeholder app.

**Fix:**
```bash
# BEFORE (wrong):
zip -r app.zip ./publish/

# AFTER (correct):
cd ./publish && zip -r ../app.zip .
```
The `cd` + `.` means files land at the zip root, not inside a subfolder.

**Key lesson:** For Azure App Service deployments, always zip the *contents* of the publish folder, not the folder itself. The files must be at the root of the zip.

---

## Issue #17 — Service Principal Lost All Roles After RG Deletion

**When:** Terraform Apply (re-deploy after destroy)
**Error:** `403 Forbidden — does not have authorization to perform action Microsoft.Resources/subscriptions/resourceGroups/read`

**Why it happened:**
The SP's role assignments were scoped to `rg-netwrix-dev`. When the resource group was deleted (`az group delete`), Azure automatically deleted all role assignments scoped to it. On re-deploy, the SP had zero permissions.

**Fix:**
Re-assigned at **subscription scope** so roles survive future resource group teardowns:
```bash
az role assignment create \
  --assignee "9e17a4f1-f7e0-4725-a815-7dcb19cca4f0" \
  --role "Contributor" \
  --scope "/subscriptions/69a76f8c-..."

az role assignment create \
  --assignee "9e17a4f1-f7e0-4725-a815-7dcb19cca4f0" \
  --role "User Access Administrator" \
  --scope "/subscriptions/69a76f8c-..."
```

**Key lesson:** For CI/CD service principals, always assign roles at subscription scope (or management group scope). Resource group-scoped assignments are lost when the RG is deleted — which defeats the purpose of automated re-deployment.

---

## Issue #18 — Stale Terraform Plan

**When:** Terraform Apply (rerun after clearing state)
**Error:** `Saved plan is stale`

**Why it happened:**
The plan artifact was generated against an empty state blob. Between `plan` and `apply`, we wiped the state file entirely. Terraform detected the state had changed and refused to apply a plan that was no longer valid.

**Fix:**
Triggered a completely fresh pipeline run (`git commit --allow-empty`), which generated a new plan against the now-correct (empty) state.

**Key lesson:** `terraform apply planfile` will always fail if the state changes after the plan was created. This is a deliberate safety mechanism — never bypass it. If a plan goes stale, just re-run the full plan → apply cycle.

---

## Issue #19 — Key Vault Resources Already Exist After Soft-Delete Recovery

**When:** Terraform Apply (re-deploy after destroy — second attempt)
**Error:**
```
Error: a resource with the ID "https://kv-netwrix-dev.vault.azure.net/certificates/appgw-tls-dev/..." already exists
Error: a resource with the ID "https://kv-netwrix-dev.vault.azure.net/secrets/db-connection-string/..." already exists
Error: a resource with the ID "https://kv-netwrix-dev.vault.azure.net/secrets/appinsights-connection-string/..." already exists
```

**Why it happened:**
The Key Vault has `purge_protection_enabled = true` and soft-delete, so when the resource group was deleted, the KV entered **soft-deleted state** rather than being permanently destroyed. The Terraform provider (configured with `recover_soft_deleted_key_vaults = true`) automatically recovered the KV during the next apply — including all its existing **certificates** and **secrets**.

The Terraform state was wiped (Issue #18 workaround), so state was empty. When Terraform tried to create the cert and secrets, they already existed inside the recovered KV → conflict error.

**Why this only affected 3 resources:**
The KV itself was handled transparently (provider auto-recovered it). Other resources (RG, VNet, subnets, SQL, App GW policy, App Insights, etc.) were recreated fresh because they don't have soft-delete. Only KV objects (certs/secrets/keys) survive deletion inside a recovered vault.

**Fix:**
1. Granted local user `Key Vault Secrets Officer` RBAC role on the KV (needed to read secrets during import):
   ```bash
   az role assignment create \
     --role "Key Vault Secrets Officer" \
     --assignee "<user-oid>" \
     --scope "/subscriptions/.../resourceGroups/rg-netwrix-dev/providers/Microsoft.KeyVault/vaults/kv-netwrix-dev"
   ```
2. Imported the 3 conflicting resources into Terraform state:
   ```bash
   terraform import "module.key_vault.azurerm_key_vault_certificate.appgw_tls" \
     "https://kv-netwrix-dev.vault.azure.net/certificates/appgw-tls-dev/<version>"

   terraform import "module.key_vault.azurerm_key_vault_secret.db_connection_string" \
     "https://kv-netwrix-dev.vault.azure.net/secrets/db-connection-string/<version>"

   terraform import "module.key_vault.azurerm_key_vault_secret.appinsights_connection_string" \
     "https://kv-netwrix-dev.vault.azure.net/secrets/appinsights-connection-string/<version>"
   ```
3. Triggered a fresh pipeline run → Terraform Apply sees the resources are already in state and skips creating them.

**Note on RBAC for local terraform import:**
The TF CLI uses your personal Azure CLI token. The Key Vault uses RBAC (`rbac_authorization_enabled = true`). Two separate data-plane roles are required:
- `Key Vault Secrets Officer` — to read/import secrets
- `Key Vault Certificates Officer` — to read/import certificates

The initial import attempt granted only `Key Vault Secrets Officer`. The certificate import (`azurerm_key_vault_certificate`) failed with `403 ForbiddenByRbac` on the **second attempt** because `Key Vault Certificates Officer` was not granted. After granting it and waiting ~60s for propagation, the cert import succeeded.

Always grant **both** roles before running `terraform import` on a Key Vault that has both secrets and certificates.

**Key lesson:** When re-deploying after a destroy, any Key Vault with `purge_protection_enabled = true` will be auto-recovered with all its contents intact. If the Terraform state was cleared between destroy and re-deploy, the KV objects (certs, secrets, keys) will conflict. The fix is always `terraform import` — bring the existing objects into state so Terraform adopts rather than recreates them.

---

## Issue #20 — App Gateway Diagnostic Setting Already Exists After Partial Apply

**When:** Terraform Apply (re-deploy — after partial apply failed mid-way on cert conflict)
**Error:**
```
Error: a resource with the ID ".../applicationGateways/appgw-netwrix-dev|diag-appgw-netwrix-dev" already exists
```

**Why it happened:**
The previous apply (run `24286485681`) failed on the KV certificate conflict (Issue #19 fix was incomplete — the cert import succeeded locally but the pipeline's state copy didn't reflect it yet). That apply was already well into apply — it had created the App Gateway and its diagnostic setting before it hit the cert error.

When the next run's apply started fresh, it found `azurerm_monitor_diagnostic_setting.appgw` already in Azure but not in the local state snapshot used by the pipeline → "already exists" conflict.

**Why the pattern keeps repeating:**
Each partial apply failure creates resources in Azure that land in the remote state blob at that point in time. But when apply aborts mid-run, later resources get created without being recorded. The plan for the next run sees the gap and tries to create them again.

**Fix:**
```bash
terraform import "module.monitoring.azurerm_monitor_diagnostic_setting.appgw" \
  "/subscriptions/.../resourceGroups/rg-netwrix-dev/providers/Microsoft.Network/applicationGateways/appgw-netwrix-dev|diag-appgw-netwrix-dev"
```
Note the `azurerm_monitor_diagnostic_setting` import ID format uses `|` (pipe) as a separator between the target resource ID and the diagnostic setting name.

**Key lesson:** Every partial apply leaves a "drift gap" — resources exist in Azure but not in state. Before retrying after any apply failure, run `terraform state list` and compare against `az resource list` in the resource group. Import anything that appears in Azure but not in state before the next pipeline run.

---

## Summary Table

| # | Stage | Error | Root Cause | Fix |
|---|---|---|---|---|
| 1 | Security Gates | Checkov violations | Missing security configs in Terraform | Added configs + justified skip_checks |
| 2 | TF Plan | 403 on state backend | Storage key access disabled | AAD auth + Storage Blob Contributor role |
| 3 | TF Plan | Missing argument | health_check_path needs partner arg | Added health_check_eviction_time_in_min |
| 4 | TF Apply | OIDC AADSTS700213 | Wrong federated credential subject | Added environment-scoped federated credential |
| 5 | TF Apply | RG already exists | Manually pre-created resource | terraform import |
| 6 | TF Apply | SKU quota = 0 | P1v3 not available in subscription | Downgraded to B2 |
| 7 | TF Apply | SQL license_type invalid | Serverless SKU doesn't support it | Removed license_type |
| 8 | TF Apply | KV 403 ForbiddenByConnection | KV created with public access disabled | Enabled public access + updated Terraform |
| 9 | TF Apply | WAF rule name invalid | Hyphens not allowed | Renamed to BlockKnownScanners |
| 10 | TF Plan | fmt check failed | Whitespace misalignment after edits | terraform fmt -recursive |
| 11 | TF Apply | WEBSITE_VNET_ROUTE_ALL error | azurerm v4 breaking change | Moved to vnet_route_all_enabled in site_config |
| 12 | TF Apply | SSL cert empty block | App GW needs real cert data | Created self-signed cert in Key Vault |
| 13 | Deploy | 403 on deploy | SCM blocked by public_network_access=false | Enabled public access |
| 14 | Smoke Test | 403 | Hitting App Service directly | Changed to hit App Gateway IP |
| 15a | Smoke Test | 502 | App GW NATs traffic via public IP | Switched to VNet subnet rule + service endpoint |
| 15b | Smoke Test | 502 | MI principal replaced, KV role orphaned | Re-granted Key Vault Secrets User to new MI |
| 16 | Smoke Test | 404 | Zip nested publish/ folder | cd ./publish && zip -r ../app.zip . |
| 17 | TF Apply | 403 on RG read | SP roles deleted with RG | Re-assigned at subscription scope |
| 18 | TF Apply | Stale plan | State cleared between plan and apply | Fresh pipeline run |
| 19 | TF Apply | KV resources already exist | KV soft-delete recovery restored cert+secrets; state was empty | terraform import for 3 KV objects |
| 20 | TF Apply | Diag setting already exists | Partial apply created App GW diag setting before failing; not in state | terraform import for diagnostic setting |
