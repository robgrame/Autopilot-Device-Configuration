# Troubleshooting

## Triage sequence

1. Identify the failed execution correlation ID.
2. Read `ExecutionStarted` to confirm dry-run and inventory provider.
3. Read `ExecutionFailed.ErrorClass`.
4. Classify the failure as configuration, inventory, authentication,
   authorization, transient, or per-device.
5. Review recent app-setting, role-assignment, deployment, and inventory changes.
6. Apply the smallest corrective action.
7. Re-run in dry-run before enabling writes.

## Common problems

### Managed Identity endpoint variables are unavailable

The operation is running outside Azure Functions, or the Function identity is
not available. Use mocked token acquisition in tests and confirm the Function
has a system-assigned Managed Identity.

### Microsoft Graph returns HTTP 401

Confirm the intended tenant, Managed Identity endpoint, and service principal.
Restart after identity changes and review Entra sign-in logs.

### Microsoft Graph returns HTTP 403

Grant and verify `DeviceManagementServiceConfig.ReadWrite.All`:

```powershell
.\scripts\Grant-GraphPermission.ps1 `
  -ResourceGroupName '<resource-group>' `
  -FunctionAppName '<function-app>'
```

### Azure Storage returns HTTP 403

Review Blob data-plane role assignments, Function principal ID, and RBAC
propagation. Redeploy the intended role assignments when necessary.

### Inventory Blob returns HTTP 404

Publish inventory and confirm the path is `inventory/inventory.json`:

```powershell
.\scripts\Publish-Inventory.ps1 `
  -SubscriptionId '<subscription-id>' `
  -ResourceGroupName '<resource-group>' `
  -FunctionAppName '<function-app>' `
  -StorageAccountName '<storage-account>' `
  -InventoryPath '.\inventory.json'
```

### Blob URL configuration is rejected

The URL must use HTTPS, target `*.blob.core.windows.net`, include a container and
Blob name, and contain no query string or SAS token.

### Inventory is invalid JSON

```powershell
Get-Content -Raw .\inventory.json | ConvertFrom-Json | Out-Null
```

Confirm the UTF-8 file is no larger than 5 MB.

### No records are processed

Check the active provider, package path or Blob URL, empty inventory, validation
events, and eligibility events. An empty JSON array is valid and produces a
zero-record summary.

### Device cannot be correlated

Verify the exact serial, whitespace, duplicate Autopilot registrations,
duplicate normalized inventory serials, and Autopilot registration state.
Partial matching is intentionally unsupported.

### Device is ineligible

Review `EligibleForAutomation`, provisioning method, lifecycle state, join type,
legacy/exclusion/conflict flags, and pilot membership.

### Device Name or Group Tag validation fails

Default patterns:

```regex
Device Name: ^[A-Za-z][A-Za-z0-9-]{0,14}$
Group Tag:   ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$
```

### Write mode cannot be enabled

`PILOT_SERIAL_NUMBERS` must contain at least one explicitly approved serial.

### Enrolled Windows device name does not change immediately

Updating the Autopilot display name does not immediately rename an already
enrolled Windows device. It applies during a later supported enrollment/OOBE
flow. Group Tag changes can affect dynamic membership sooner.

### `azd provision` resets or rejects the provider

Persist the provider in the selected environment:

```powershell
azd env set INVENTORY_PROVIDER storage-blob
```

Fresh environments default to `package-json`.

### Function execution times out

Inspect tenant size, Graph throttling, retries, and duration. Reduce pilot scope
and consider resumable orchestration only when measurements justify it.

## Diagnostic collection

Collect UTC timestamp, correlation ID, error class, Function name, active
provider, approved inventory version, affected serials, recent role/configuration
changes, device events, and the execution summary.

Never collect or share access tokens, authorization headers, account keys, or
SAS tokens.

