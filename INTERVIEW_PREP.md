# Interview Preparation Guide
### Netwrix Senior DevOps Engineer Assessment

Progress key: ⬜ Not started · 🔄 In progress · ✅ Understood

---

## Block 1 — The Big Picture (Architecture)

- ✅ 1. Traffic flow: user → App Gateway → App Service → SQL
- ✅ 2. Why each Azure service was chosen
- ✅ 3. Network segmentation — 4 subnets and why they're separated
- ✅ 4. Two security layers on App Service (IP restriction + public_network_access)

## Block 2 — Security Design

- ✅ 5. Managed Identity — what problem it solves, no passwords
- ✅ 6. Key Vault references — how secrets never appear in plain text
- ✅ 7. RBAC on Key Vault — modern model vs legacy access policies
- ✅ 8. Private endpoints — what they do, which resources have them, why
- ✅ 9. WAF — OWASP ruleset, Prevention mode, custom BlockKnownScanners rule

## Block 3 — Terraform & IaC

- ✅ 10. Terraform state — what it is, why in Azure Blob, why AAD auth
- ✅ 11. Module structure — 6 modules, how outputs wire them together
- ✅ 12. dev/main.tf — dependency chain (why monitoring is last, etc.)
- ✅ 13. User-assigned identity for App Gateway — why in root module (circular dependency)
- ✅ 14. What happens on destroy with purge_protection_enabled = true

## Block 4 — CI/CD Pipeline

- ✅ 15. OIDC — what it is, why better than a client secret, how federated credential works
- ✅ 16. The 5-job pipeline — what each job does
- ✅ 17. dev-deploy environment gate — who approves, what it protects
- ✅ 18. Checkov — SAST, what it checked, why certain checks were skipped
- ✅ 19. Gitleaks — what it scans for, when it runs

## Block 5 — The .NET App

- ✅ 20. Program.cs — what /health returns and why
- ✅ 21. Application Insights — what telemetry you'd see in production

## Block 6 — Trade-offs & Production Gaps

- ✅ 22. 3 things to change for production (self-hosted runner, real TLS cert, multi-region)
- ✅ 23. App Gateway TLS cert — why self-signed is ok for dev, what you'd use in prod
- ✅ 24. Smoke test via IP — why, and what the real production fix is
