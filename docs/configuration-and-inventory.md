# Configuration and Inventory

## Application settings

| Setting | Default | Validation | Purpose |
|---------|---------|------------|---------|
| `DRY_RUN` | `true` | `true` or `false` | Prevents Graph updates when enabled. |
| `TIMER_SCHEDULE` | `0 0 */6 * * *` | Azure Functions NCRONTAB | Runs every six hours. |
| `INVENTORY_PROVIDER` | `package-json` | `package-json` or `storage-blob` | Selects the inventory source. |
| `INVENTORY_PATH` | `inventory/sample-inventory.json` | File path | Package inventory path. |
| `INVENTORY_STORAGE_BLOB_URL` | Provisioned Blob URL | Public Azure HTTPS Blob URL; no query | Private Blob source. |
| `DEVICE_NAME_VALIDATION_PATTERN` | `^[A-Za-z][A-Za-z0-9-]{0,14}$` | Valid regex | Customer Device Name convention. |
| `GROUP_TAG_VALIDATION_PATTERN` | `^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$` | Valid regex | Customer Group Tag convention. |
| `PILOT_SERIAL_NUMBERS` | Empty | Comma-separated serials | Write-mode allow-list. |
| `LOG_LEVEL` | `Information` | String | Runtime log level. |
| `GRAPH_API_VERSION` | `v1.0` | `v1.0` or `beta` | Microsoft Graph API version. |
| `MAX_RETRY_COUNT` | `4` | Integer `0` to `10` | Retries after the first request. |
| `RETRY_BASE_DELAY_SECONDS` | `2` | Integer `1` to `60` | Exponential backoff base. |
| `GRAPH_REQUEST_TIMEOUT_SECONDS` | `100` | Integer `10` to `300` | Per-request timeout. |

Invalid settings throw a classified configuration error before device
processing. Write mode is rejected when the pilot list is empty.

## Inventory providers

### Package JSON

Use for:

- local development;
- repository demonstrations;
- first bootstrap deployment;
- controlled inventory that changes only with a release.

Configuration:

```text
INVENTORY_PROVIDER=package-json
INVENTORY_PATH=inventory/sample-inventory.json
```

### Private Azure Blob

Use for routine inventory updates without redeploying code.

Configuration:

```text
INVENTORY_PROVIDER=storage-blob
INVENTORY_STORAGE_BLOB_URL=https://<account>.blob.core.windows.net/inventory/inventory.json
```

The URL:

- must use HTTPS;
- must target public Azure `blob.core.windows.net`;
- must contain a container and Blob path;
- must not contain a query string or SAS token.

The Function requests a Managed Identity token for
`https://storage.azure.com/` and downloads the Blob through the Storage REST API.

## Inventory schema

### Required business fields

```json
{
  "SerialNumber": "SERIAL001",
  "DeviceName": "IT-LT-00123",
  "GroupTag": "NATIVE-IT-LAPTOP",
  "EligibleForAutomation": true
}
```

### Required conservative eligibility fields

```json
{
  "ProvisioningMethod": "Autopilot",
  "LifecycleState": "Pilot",
  "JoinType": "MicrosoftEntraJoined",
  "Legacy": false,
  "Excluded": false,
  "ConflictingProvisioningInfo": false
}
```

### Complete example

```json
[
  {
    "SerialNumber": "SERIAL001",
    "DeviceName": "IT-LT-00123",
    "GroupTag": "NATIVE-IT-LAPTOP",
    "EligibleForAutomation": true,
    "ProvisioningMethod": "Autopilot",
    "LifecycleState": "Pilot",
    "JoinType": "MicrosoftEntraJoined",
    "Legacy": false,
    "Excluded": false,
    "ConflictingProvisioningInfo": false
  }
]
```

All committed examples are fictitious.

## Field rules

### SerialNumber

- Trimmed and normalized to uppercase.
- Empty serials are rejected.
- Partial, prefix, suffix, and substring matches are not used.
- Duplicate normalized inventory serials are rejected.
- Multiple Autopilot identities with the same normalized serial are ambiguous
  and rejected.

### DeviceName

Default pattern:

```regex
^[A-Za-z][A-Za-z0-9-]{0,14}$
```

The name:

- starts with a letter;
- contains only letters, numbers, and hyphens;
- is at most 15 characters;
- is never truncated or rewritten by the application;
- must be unique among desired inventory names.

### GroupTag

Default pattern:

```regex
^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$
```

The tag is never truncated or rewritten.

### Eligibility

A record is eligible only when:

- `EligibleForAutomation` is explicitly `true`;
- `Legacy`, `Excluded`, and `ConflictingProvisioningInfo` are not `true`;
- `ProvisioningMethod` is `Autopilot` or `CloudNative`;
- `LifecycleState` is `Approved`, `Pilot`, or `Ready`;
- `JoinType` is `MicrosoftEntraJoined` or `Pending`;
- the serial is in the pilot list when a list is configured.

Missing or unknown metadata fails closed.

## File constraints

- JSON object or array is accepted.
- Empty arrays are valid and produce a zero-record execution.
- Maximum UTF-8 content size is 5 MB.
- Invalid JSON stops the execution.
- Records missing required fields are rejected during validation.

## Publish inventory

```powershell
.\scripts\Publish-Inventory.ps1 `
  -SubscriptionId '<customer-subscription-id>' `
  -ResourceGroupName '<resource-group>' `
  -FunctionAppName '<function-app>' `
  -StorageAccountName '<storage-account>' `
  -InventoryPath '.\inventory.json'
```

Required operator permissions:

- Storage Blob Data Contributor;
- permission to update Function App settings.

## Change procedure

1. Export or retain the currently approved inventory.
2. Prepare the new inventory in source control or the customer change system.
3. Review serials, Device Names, Group Tags, and eligibility metadata.
4. Validate dependencies on Group Tag-based dynamic groups.
5. Publish the file.
6. Run in dry-run.
7. Review `DeviceWouldUpdate`, validation failures, and eligibility failures.
8. Approve the pilot.
9. Enable write mode only for named pilot serials.
10. Verify the resulting Autopilot and downstream targeting state.

