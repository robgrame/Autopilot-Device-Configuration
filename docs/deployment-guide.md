# Deployment Guide

## Deployment status

The repository is prepared and locally validated, but Azure deployment is
intentionally blocked until an authorized customer tenant, subscription, and
region are confirmed.

Do not deploy into an unrelated subscription visible to the current operator.

## Prerequisites

### Customer platform

- Azure subscription approved for the workload.
- Microsoft Intune licensing and Windows Autopilot enabled.
- At least one controlled Autopilot test device.
- Approved Device Name and Group Tag conventions.
- Review of dynamic Entra groups and Intune assignments that depend on Group Tag.

### Operator roles

- Contributor on the subscription or target resource group.
- Owner or User Access Administrator for Azure RBAC creation.
- Privileged Role Administrator for the post-deployment Graph app-role assignment.
- Storage Blob Data Contributor for inventory publication.
- Permission to update Function App configuration.

### Local tools

```text
PowerShell 7.4+
Azure CLI
Azure Developer CLI (azd)
Pester 5.5+
Azure Functions Core Tools v4 (optional)
```

Authenticate to the intended customer tenant:

```powershell
az login --tenant '<customer-tenant-id>'
az account set --subscription '<customer-subscription-id>'
az account show --output table
azd auth login
```

## Pre-deployment validation

1. Confirm the Azure account and tenant.
2. Confirm the customer subscription ID.
3. Select an allowed public Azure region.
4. Review Azure Policy restrictions and regional quotas.
5. Review the inventory and pilot serials.
6. Keep `DRY_RUN=true`.
7. Run local validation:

```powershell
.\scripts\Invoke-Tests.ps1
az bicep build --stdout --file .\infra\main.bicep | Out-Null
```

## Deploy infrastructure and code

```powershell
.\scripts\Deploy.ps1 `
  -EnvironmentName 'pilot' `
  -SubscriptionId '<customer-subscription-id>' `
  -Location 'westeurope'
```

The script:

1. verifies AZD and Azure CLI authentication;
2. verifies the selected subscription;
3. selects or creates the AZD environment;
4. records subscription, location, and the default inventory provider;
5. runs `azd provision --no-prompt`;
6. waits for Azure RBAC propagation;
7. runs `azd deploy --no-prompt`;
8. verifies that `DRY_RUN` remains `true`.

## Provisioned resources

- Resource group
- Azure Functions Flex Consumption plan
- PowerShell Function App
- Storage Account
- `app-package` and `inventory` Blob containers
- Log Analytics workspace
- Application Insights
- System-assigned Managed Identity
- Azure RBAC assignments required by the Function runtime

## Grant the Microsoft Graph app role

Run as Privileged Role Administrator:

```powershell
.\scripts\Grant-GraphPermission.ps1 `
  -ResourceGroupName '<resource-group>' `
  -FunctionAppName '<function-app>'
```

Expected permission:

```text
DeviceManagementServiceConfig.ReadWrite.All
```

The script is idempotent and verifies the assignment.

## Activate private Blob inventory

Prepare an approved JSON inventory and run:

```powershell
.\scripts\Publish-Inventory.ps1 `
  -SubscriptionId '<customer-subscription-id>' `
  -ResourceGroupName '<resource-group>' `
  -FunctionAppName '<function-app>' `
  -StorageAccountName '<storage-account>' `
  -InventoryPath '.\inventory.json'
```

The script:

- rejects missing, invalid, or larger-than-5-MB files;
- verifies required business properties;
- creates or accesses the private `inventory` container;
- uploads `inventory/inventory.json` with Entra authentication;
- sets the Function App to `INVENTORY_PROVIDER=storage-blob`;
- attempts to persist the choice in the selected AZD environment.

If AZD environment persistence fails, the Function App remains configured and
the script prints this required command:

```powershell
azd env set INVENTORY_PROVIDER storage-blob
```

## Validate dry-run

Keep the initial pilot small.

1. Confirm `DRY_RUN=true`.
2. Configure only approved pilot serials.
3. Run the timer from the Azure portal or wait for the schedule.
4. Confirm `ExecutionStarted` reports the correct provider and dry-run state.
5. Confirm expected records produce `DeviceWouldUpdate`.
6. Confirm no `DeviceUpdated` event exists.
7. Confirm the Autopilot records are unchanged.

Example query:

```kusto
traces
| where timestamp > ago(24h)
| where message has '"EventName":"DeviceWouldUpdate"'
| order by timestamp desc
```

## Enable controlled write mode

```powershell
.\scripts\Set-DryRun.ps1 `
  -ResourceGroupName '<resource-group>' `
  -FunctionAppName '<function-app>' `
  -DryRun $false `
  -PilotSerialNumbers 'SERIAL001'
```

Before enabling:

- approve every pilot serial;
- approve desired Device Names and Group Tags;
- verify Graph permission;
- review Group Tag-based targeting;
- review all dry-run outcomes;
- confirm a rollback inventory is available.

## Post-deployment verification

- [ ] Function App is running on PowerShell 7.4.
- [ ] Only the timer trigger exists.
- [ ] Managed Identity is enabled.
- [ ] Shared Key access is disabled.
- [ ] Blob public access is disabled.
- [ ] Application Insights local auth is disabled.
- [ ] Graph app role is assigned.
- [ ] `DRY_RUN=true`.
- [ ] Correct inventory provider is active.
- [ ] Pilot serial allow-list is correct.
- [ ] Execution summary is present in telemetry.
- [ ] Dry-run did not change Autopilot.

## Rollback

### Stop processing

```powershell
.\scripts\Set-TimerState.ps1 `
  -ResourceGroupName '<resource-group>' `
  -FunctionAppName '<function-app>' `
  -Disabled $true
```

### Return to dry-run

```powershell
.\scripts\Set-DryRun.ps1 `
  -ResourceGroupName '<resource-group>' `
  -FunctionAppName '<function-app>' `
  -DryRun $true
```

### Restore previous values

Use the approved pre-change inventory and `DeviceUpdated` telemetry to prepare
the reverse desired state, publish it, validate in dry-run, and execute only
after approval.

### Remove the Azure environment

Resource deletion is a separate, explicitly approved activity. Follow customer
retention requirements for telemetry and inventory before deleting resources.

