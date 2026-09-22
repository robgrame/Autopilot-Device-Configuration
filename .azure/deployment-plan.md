# Azure Deployment Plan

> **Status:** Ready for Validation

Generated: 2026-09-22

---

## 1. Project Overview

**Goal:** Build a minimal, secure, timer-triggered Azure Functions solution that correlates an approved inventory with Windows Autopilot identities by exact normalized serial number and updates the Autopilot display name and Group Tag through Microsoft Graph.

**Path:** New project.

## 2. Requirements

| Attribute | Value |
|-----------|-------|
| Classification | Proof of Concept / MVP |
| Scale | Small; one scheduled batch worker |
| Budget | Cost-optimized |
| Subscription | Not selected; repository preparation only |
| Location | `westeurope` default parameter; confirm before deployment |
| Compliance | Least privilege, EU-oriented default, no credentials, sanitized logs |

No Azure deployment is authorized in this phase because the authenticated account exposes many unrelated subscriptions and no customer subscription is selected.

## 3. Components

| Component | Type | Technology | Path |
|-----------|------|------------|------|
| Autopilot timer worker | Scheduled worker | Azure Functions v4, PowerShell 7.4 | `src` |
| Inventory provider | Application component | JSON package or private Azure Blob provider behind a PowerShell interface | `src/Modules/InventoryProvider.psm1` |
| Microsoft Graph client | Application component | Direct REST with managed identity | `src/Modules/GraphClient.psm1` |
| Validation and eligibility | Application component | PowerShell modules | `src/Modules` |
| Infrastructure | IaC | AZD + Bicep | `infra` |
| Tests | Unit tests | Pester 5 | `tests` |

## 4. Recipe Selection

**Selected:** Azure Developer CLI with Bicep.

**Rationale:**

- The customer explicitly requires Bicep.
- AZD provides repeatable environment handling and separate provision/deploy steps.
- The official Azure Functions timer template supplies the Flex Consumption, storage, identity, RBAC, and monitoring baseline.
- PowerShell 7.4 is the current supported GA PowerShell runtime for Azure Functions.

## 5. Architecture

**Stack:** Serverless.

| Component | Azure service | SKU |
|-----------|---------------|-----|
| Scheduled worker | Azure Functions | Flex Consumption `FC1`, 2 GB instance |
| Runtime and deployment storage | Storage Account | Standard LRS |
| Telemetry | Application Insights | Workspace-based |
| Central logs | Log Analytics | 30-day retention |
| Authentication | System-assigned Managed Identity | No credentials |

The Function App has no HTTP trigger. The only trigger is a timer. Inventory can be read from the deployment package or a private Blob in the existing Function Storage Account. Blob access uses Managed Identity and Microsoft Entra authorization; no account key or SAS token is used. The selected provider is persisted in the AZD environment so later provisioning does not silently reset it. The Function calls Microsoft Graph `v1.0` directly to avoid the Microsoft Graph PowerShell SDK package size and cold-start cost.

## 6. Microsoft Graph Design

- List: `GET /v1.0/deviceManagement/windowsAutopilotDeviceIdentities`
- Update: `POST /v1.0/deviceManagement/windowsAutopilotDeviceIdentities/{id}/updateDeviceProperties`
- Update body properties: `displayName`, `groupTag`
- Application permission: `DeviceManagementServiceConfig.ReadWrite.All`
- Administrator required to grant the Microsoft Graph app role: Privileged Role Administrator
- Permission assignment is a post-deployment tenant operation and is not embedded in ARM/Bicep.

The permission-assignment script resolves the Microsoft Graph service principal and app-role ID at runtime and is idempotent.

## 7. Security and Safety

- System-assigned Managed Identity only.
- Private Blob inventory ingestion reuses the existing Storage Account and rejects SAS-bearing URLs.
- Blob inventory URLs are intentionally restricted to public Azure in this MVP.
- No client secrets, certificates, stored tokens, or interactive runtime authentication.
- Storage shared-key access disabled.
- TLS 1.2 minimum and HTTPS only.
- Application Insights local authentication disabled.
- `DRY_RUN=true` by default.
- Write mode requires a non-empty pilot serial allow-list.
- Exact normalized serial matches only; duplicates and ambiguity are fail-closed.
- Explicit inventory eligibility plus provisioning, lifecycle, join-type, legacy, exclusion, and conflict checks.
- Structured logs exclude tokens, authorization headers, and full Graph response bodies.
- Transient Graph and Blob Storage errors use bounded exponential backoff with jitter.

## 8. Provisioning Limit Checklist

Deployment is not part of this phase, so subscription usage and regional quota cannot be queried safely.

| Resource type | Number to deploy | Capacity status | Notes |
|---------------|------------------|-----------------|-------|
| `Microsoft.Web/serverfarms` | 1 | Not evaluated | Requires selected customer subscription and region |
| `Microsoft.Web/sites` | 1 | Not evaluated | Flex Consumption Function App |
| `Microsoft.Storage/storageAccounts` | 1 | Not evaluated | Runtime and deployment package |
| `Microsoft.OperationalInsights/workspaces` | 1 | Not evaluated | Central logging |
| `Microsoft.Insights/components` | 1 | Not evaluated | Application Insights |

Quota validation is a deployment prerequisite, not a repository-generation prerequisite. It must be completed with the `azure-quotas` workflow after the customer subscription and region are confirmed.

## 9. Functional Verification

- Unit tests: Pester tests with all Microsoft Graph operations mocked.
- Static checks: PowerShell parser, Bicep build, JSON parsing, repository secret scan.
- Live Graph validation: intentionally not performed without a customer tenant and controlled Autopilot device.
- Azure deployment validation: deferred until subscription and location confirmation.

## 10. Files to Generate

| File or folder | Purpose |
|----------------|---------|
| `README.md` | Architecture, security, deployment, operations, rollback |
| `azure.yaml` | AZD service definition |
| `infra` | Bicep infrastructure |
| `src` | Azure Function and modules |
| `src/inventory` | Fictitious MVP inventory |
| `tests` | Pester unit tests |
| `scripts` | Deployment, permissions, configuration, and test helpers |
| `.github/workflows` | CI validation |

## 11. Known Limitations

- The packaged JSON inventory requires a code deployment to change.
- The optional Blob provider removes that deployment requirement while retaining the package provider for bootstrap and local testing.
- HTTP ingestion is intentionally deferred because it adds an externally reachable trigger, authentication policy, request validation, and concurrency/audit concerns.
- Join type cannot be safely derived from the Autopilot identity alone. The MVP therefore requires explicit approved inventory metadata and fails closed; production should add the managed-device and Entra-device lookups.
- Execution history is retained in telemetry rather than a dedicated change-history store.
- No private endpoints are enabled by default for the cost-optimized MVP, although the infrastructure supports optional VNet integration.
- Group Tag changes can alter dynamic group membership and downstream Intune assignments.

## 12. Production Evolution

Replace the packaged provider with a CMDB/API provider, add managed-device and Entra join-state resolution, approval workflow, durable change history, alerts and dashboards, private networking, policy-as-code, and CI/CD promotion environments.

## 13. Execution Checklist

### Planning

- [x] Analyze workspace
- [x] Gather requirements from the customer brief
- [x] Select AZD + Bicep recipe
- [x] Verify Graph endpoints and permissions
- [x] Verify PowerShell runtime and official timer template
- [x] Record deployment-context safety block
- [x] User authorized immediate implementation

### Execution

- [x] Generate Function application
- [x] Generate Bicep and AZD artifacts
- [x] Add tests, scripts, sample inventory, and README
- [x] Run local functional verification
- [x] Complete rubber-duck and security reviews and apply findings
- [x] Set status to `Ready for Validation`

### Validation and Deployment

- [ ] Invoke `azure-validate`
- [ ] All validation checks pass
  - [x] 1. AZD Installation
  - [x] 2. Schema Validation
  - [x] 3. Environment Setup
  - [ ] 4. Authentication Check
  - [ ] 5. Subscription/Location Check
  - [x] 6. Aspire Pre-Provisioning Checks - not applicable
  - [ ] 7. Provision Preview
  - [x] 8. Build Verification
  - [x] 9. Docker Build Context Validation - not applicable
  - [x] 10. Package Validation
  - [ ] 11. Azure Policy Validation
  - [x] 12. Aspire Post-Provisioning Checks - not applicable
- [ ] Confirm customer subscription, tenant, resource group, and region
- [ ] Check policies and quotas
- [ ] Invoke `azure-deploy`

## 14. Validation Proof

| Check | Command | Result | Timestamp |
|-------|---------|--------|-----------|
| PowerShell and JSON syntax | PowerShell parser and `ConvertFrom-Json` across repository | Pass | 2026-09-22 |
| Unit tests | `.\scripts\Invoke-Tests.ps1` | 44 passed, 0 failed | 2026-09-22 |
| Bicep compilation | `az bicep build --stdout --file infra\main.bicep` | Pass | 2026-09-22 |
| Secret pattern scan | Repository regex scan excluding documentation examples | No committed secret found | 2026-09-22 |
| AZD installation | `azd version` | 1.34.1 | 2026-09-22 |
| AZD schema/package | `azd package --no-prompt` | Package created successfully | 2026-09-22 |

Validation remains intentionally incomplete: AZD is not authenticated and no customer subscription or region has been approved. Provision preview, Azure Policy validation, quota checks, and deployment must not run against the unrelated subscriptions visible to the current account.
