# Project Documentation

This directory is the documentation portal for **Autopilot Device Configuration**.
It is intended for project sponsors, solution architects, Azure and Intune
administrators, security reviewers, operators, and maintainers.

## Document map

| Document | Audience | Purpose |
|----------|----------|---------|
| [Solution overview](solution-overview.md) | Sponsors, service owners, architects | Scope, outcomes, workflow, assumptions, and acceptance criteria. |
| [Architecture](architecture.md) | Architects, engineers | Components, runtime flow, Azure resources, integration design, and technical decisions. |
| [Security and permissions](security-and-permissions.md) | Security, Entra, Azure, and Intune administrators | Identities, RBAC, Graph permissions, trust boundaries, controls, and residual risks. |
| [Deployment guide](deployment-guide.md) | Azure platform engineers | Prerequisites, deployment, Graph authorization, Blob activation, validation, and rollback. |
| [Configuration and inventory](configuration-and-inventory.md) | Application owners, inventory administrators | Application settings, inventory schema, validation rules, and safe update procedures. |
| [Operations runbook](operations-runbook.md) | Service desk, operations, Intune administrators | Monitoring, scheduled operations, dry-run, write-mode controls, incident response, and maintenance. |
| [Testing and quality](testing-and-quality.md) | Developers, reviewers, release managers | Test scope, local validation, CI checks, release gates, and evidence. |
| [Troubleshooting](troubleshooting.md) | Operations and engineering | Symptoms, diagnostic queries, common causes, and corrective actions. |
| [Project governance](project-governance.md) | Project manager, customer stakeholders | Roles, deliverables, decisions, constraints, rollout stages, and completion criteria. |
| [Customer email](email/Autopilot-Device-Configuration-Solution.eml) | Account and project teams | Editable Outlook-compatible message describing the solution and linking the repository. |

## Source of truth

- `README.md` is the public product introduction and quick-start guide.
- `docs/` contains the detailed project and operational documentation.
- `.azure/deployment-plan.md` records Azure preparation and validation status.
- `infra/` is the source of truth for provisioned Azure resources.
- `src/Modules/Configuration.psm1` is the source of truth for runtime defaults and validation.
- `tests/AutopilotAutomation.Tests.ps1` is the executable behavior specification.

## Current release

- Version: `0.2.1`
- Runtime: Azure Functions v4, PowerShell 7.4
- Graph API: Microsoft Graph `v1.0`
- Inventory providers: packaged JSON and private Azure Blob
- Default safety mode: `DRY_RUN=true`
- Deployment status: repository ready; customer subscription and tenant authorization still required

