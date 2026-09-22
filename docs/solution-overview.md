# Solution Overview

## Executive summary

Autopilot Device Configuration replaces a manual, error-prone process for
assigning Windows Autopilot Device Names and Group Tags with a controlled,
auditable Azure-hosted workflow.

The solution correlates an approved inventory with Windows Autopilot identities
using an exact normalized serial-number match. It validates the desired values
and device eligibility, compares them with the current Autopilot record, and
either records the proposed change in dry-run mode or applies the approved
change through Microsoft Graph.

The workload runs as a timer-triggered Azure Function. It has no custom public
HTTP endpoint and uses a system-assigned Managed Identity instead of stored
credentials.

## Business outcomes

- Reduce manual Device Name and Group Tag administration.
- Enforce approved naming and tagging conventions consistently.
- Prevent partial, ambiguous, duplicate, or unauthorized device matches.
- Provide a dry-run report before any production modification.
- Maintain traceable execution summaries and per-device outcomes.
- Support inventory updates without code deployment through private Blob
  ingestion.
- Deliver repeatable Azure infrastructure and an automated validation pipeline.

## Scope

### Included

- Read Windows Autopilot identities from Microsoft Graph.
- Match inventory and Autopilot devices by exact normalized serial number.
- Validate Device Name, Group Tag, inventory uniqueness, and eligibility.
- Detect compliant devices and avoid unnecessary updates.
- Update Autopilot `displayName` and `groupTag`.
- Preserve existing user assignment fields in the update action.
- Run in dry-run or controlled pilot write mode.
- Read inventory from packaged JSON or a private Azure Blob.
- Emit structured telemetry to Application Insights.
- Provision Azure resources with Bicep and Azure Developer CLI.
- Validate behavior with tenant-independent Pester tests.

### Excluded from the MVP

- Public or private HTTP inventory ingestion.
- A user interface or approval portal.
- Direct CMDB integration.
- Automatic managed-device and Entra join-state resolution.
- Private endpoints and controlled outbound networking.
- An immutable external audit database.
- Broad production rollout without a controlled pilot.

## Primary workflow

1. The timer starts a Function execution and creates a correlation ID.
2. Runtime configuration is loaded and validated.
3. Inventory is loaded from the configured provider.
4. Inventory records and desired names are checked for duplicates.
5. All Windows Autopilot identities are retrieved with Graph pagination.
6. Serial numbers are trimmed, normalized, and matched exactly.
7. Validation and eligibility rules are applied fail-closed.
8. Current and desired Device Name and Group Tag values are compared.
9. Compliant devices are recorded without an update.
10. Dry-run executions emit `DeviceWouldUpdate`.
11. Write-mode executions update only approved pilot serials.
12. Device-level failures are isolated and the batch continues.
13. A structured execution summary is emitted.

## Safety model

The initial deployment is intentionally non-destructive:

- `DRY_RUN=true` by default;
- write mode requires a non-empty `PILOT_SERIAL_NUMBERS` allow-list;
- only exact serial matches are accepted;
- ambiguous and duplicate records are rejected;
- missing risk metadata is treated as ineligible;
- Hybrid, legacy, excluded, or conflicting records are rejected;
- field values are validated rather than truncated or rewritten;
- compliant records are not updated;
- configuration and authorization errors stop the batch.

## Stakeholders

| Stakeholder | Responsibility |
|-------------|----------------|
| Service owner | Approves scope, pilot, naming standards, and production rollout. |
| Intune administrator | Validates Autopilot behavior, Group Tag dependencies, and pilot results. |
| Azure platform engineer | Deploys and operates the Azure resources. |
| Privileged Role Administrator | Grants the Managed Identity Microsoft Graph application permission. |
| Inventory owner | Supplies and approves inventory records and lifecycle metadata. |
| Security reviewer | Reviews identities, RBAC, telemetry, and residual risk. |
| Operations team | Monitors executions and follows the runbook and troubleshooting guide. |

## Assumptions

- The customer has an active Azure subscription and Microsoft Intune licensing.
- Target devices are already registered in Windows Autopilot.
- The inventory owner can assert approved provisioning, lifecycle, and join data.
- Naming and Group Tag patterns are approved before write mode.
- Dynamic Entra groups and Intune assignments based on Group Tag are reviewed.
- A controlled Autopilot test device is available for the pilot.

## Acceptance criteria

The MVP is accepted when:

- infrastructure deploys successfully in the approved tenant and subscription;
- the Managed Identity has the documented Azure and Graph permissions;
- dry-run identifies only the approved pilot records;
- no Autopilot values change during dry-run;
- invalid, duplicate, ambiguous, and excluded records fail closed;
- the write pilot updates only allow-listed serials;
- updated values are visible in Windows Autopilot;
- telemetry contains correlation IDs and execution summaries;
- a second identical run reports the updated devices as compliant;
- rollback evidence is available from the approved inventory and telemetry.

## Repository

<https://github.com/robgrame/Autopilot-Device-Configuration>

