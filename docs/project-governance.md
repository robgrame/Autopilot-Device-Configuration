# Project Governance

## Objective

Deliver a secure MVP that automates approved Windows Autopilot Device Name and
Group Tag assignments with pilot controls, traceability, and repeatable Azure
deployment.

## Deliverables

| Deliverable | Location | Status |
|-------------|----------|--------|
| PowerShell Azure Function | `src/` | Complete |
| Microsoft Graph integration | `src/Modules/GraphClient.psm1` | Complete |
| Package and Blob inventory providers | `src/Modules/InventoryProvider.psm1` | Complete |
| Validation and eligibility engine | `src/Modules/` | Complete |
| Bicep and AZD infrastructure | `infra/`, `azure.yaml` | Complete |
| Administration scripts | `scripts/` | Complete |
| Tests and CI | `tests/`, `.github/workflows/` | Complete |
| Public product documentation | `README.md` | Complete |
| Detailed project documentation | `docs/` | Complete |
| Customer email template | `docs/email/` | Complete |
| Customer-tenant deployment | Customer environment | Pending authorization |

## Responsibility matrix

| Activity | Service owner | Azure engineer | Intune admin | Privileged Role Admin | Inventory owner | Security |
|----------|---------------|----------------|--------------|-----------------------|-----------------|----------|
| Approve scope and pilot | A | C | C | I | C | C |
| Deploy Azure resources | I | R/A | I | I | I | C |
| Grant Graph app role | I | C | C | R/A | I | C |
| Approve inventory | C | I | C | I | R/A | C |
| Publish inventory | I | C | C | I | R/A | I |
| Review dry-run | A | C | R | I | R | C |
| Enable write pilot | A | R | R | I | C | C |
| Monitor operations | I | R | R | I | C | C |
| Approve production rollout | A | C | R | I | C | C |

Legend: **R** Responsible, **A** Accountable, **C** Consulted, **I** Informed.

## Delivery stages

1. **Repository and design** - implementation, tests, documentation, CI, and
   security review. Status: complete.
2. **Customer environment validation** - tenant, subscription, region, policy,
   quota, and preview. Status: pending authorization.
3. **Dry-run pilot** - deploy, grant Graph permission, publish controlled
   inventory, and approve proposed changes. Status: pending.
4. **Controlled write pilot** - update named pilot serials and verify downstream
   effects. Status: pending.
5. **Production transition** - accept support, monitoring, inventory governance,
   and controlled expansion. Status: pending.

## Decision record

| Decision | Outcome |
|----------|---------|
| Hosting | Azure Functions Flex Consumption |
| Runtime | PowerShell 7.4 |
| Trigger | Timer only |
| Graph integration | Direct Microsoft Graph REST `v1.0` |
| Authentication | System-assigned Managed Identity |
| Infrastructure | Bicep with Azure Developer CLI |
| Default safety state | Dry-run |
| Write control | Mandatory pilot serial allow-list |
| Inventory bootstrap | Packaged JSON |
| Operational inventory | Private Blob in existing Function Storage Account |
| HTTP inventory API | Deferred |
| Telemetry | Application Insights and Log Analytics |

## Change control

Behavioral changes require requirement/risk review, implementation,
documentation, tests, version increment, review, successful local validation,
CI, and deployment only into the approved customer environment.

Inventory changes require a retained previous version, named owner and approver,
dry-run evidence, pilot scope, and post-change verification.

## Constraints

- No customer subscription or tenant is currently authorized for deployment.
- The MVP uses public Azure endpoints.
- The Function Storage Account is reused for inventory.
- Join type is supplied by approved inventory rather than resolved live.
- Group Tag changes can affect dynamic groups and Intune assignments.

## Completion criteria

- customer environment validation passes;
- deployment and permissions are verified;
- dry-run evidence is approved;
- controlled write pilot succeeds;
- support ownership and inventory governance are accepted;
- rollback and incident procedures are tested;
- final customer acceptance is recorded.

