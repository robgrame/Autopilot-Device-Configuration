# Operations Runbook

## Service description

The service is a scheduled Azure Function that evaluates approved inventory
against Windows Autopilot and proposes or applies Device Name and Group Tag
changes.

Default schedule:

```text
0 0 */6 * * *
```

The Function is stateless and idempotent. A repeat execution after a successful
update reports the device as compliant.

## Daily operational checks

- Confirm the most recent execution completed.
- Review `ExecutionSummary`.
- Investigate `ExecutionFailed` or `DeviceUpdateFailed`.
- Confirm the expected inventory provider is active.
- Confirm dry-run/write state and pilot scope.
- Review unexpected increases in validation, eligibility, or correlation failures.

## Structured events

| Event | Meaning | Operator action |
|-------|---------|-----------------|
| `ExecutionStarted` | Run started and configuration loaded. | Verify provider and `DryRun`. |
| `DeviceValidationFailed` | Inventory values are invalid or duplicated. | Correct the inventory. |
| `DeviceEligibilityFailed` | Device failed lifecycle or safety rules. | Review metadata; do not bypass without approval. |
| `DeviceCorrelationFailed` | No unique exact Autopilot match. | Verify serial and duplicate registrations. |
| `DeviceCompliant` | Desired and current values already match. | No action. |
| `DeviceWouldUpdate` | Dry-run identified an approved change. | Review before write approval. |
| `DeviceUpdated` | Graph update completed. | Verify Autopilot and downstream targeting. |
| `DeviceUpdateFailed` | One device update failed. | Investigate; other devices continue. |
| `ExecutionSummary` | Aggregate outcome and duration. | Use for service health and reporting. |
| `ExecutionFailed` | Batch-wide failure. | Follow incident triage. |

## Core queries

### Latest summaries

```kusto
traces
| where timestamp > ago(7d)
| where message has '"EventName":"ExecutionSummary"'
| extend payload = parse_json(message)
| project timestamp,
          CorrelationId=tostring(payload.CorrelationId),
          DryRun=tobool(payload.DryRun),
          Inventory=todouble(payload.InventoryRecordsLoaded),
          Matches=todouble(payload.UniqueMatches),
          Proposed=todouble(payload.ProposedUpdates),
          Updated=todouble(payload.SuccessfulUpdates),
          Failed=todouble(payload.FailedUpdates),
          DurationMs=todouble(payload.DurationMilliseconds)
| order by timestamp desc
```

### Proposed dry-run changes

```kusto
traces
| where timestamp > ago(24h)
| where message has '"EventName":"DeviceWouldUpdate"'
| extend payload = parse_json(message)
| project timestamp,
          CorrelationId=tostring(payload.CorrelationId),
          SerialNumber=tostring(payload.SerialNumber),
          CurrentDeviceName=tostring(payload.CurrentDeviceName),
          DesiredDeviceName=tostring(payload.DesiredDeviceName),
          CurrentGroupTag=tostring(payload.CurrentGroupTag),
          DesiredGroupTag=tostring(payload.DesiredGroupTag)
| order by timestamp desc
```

### Failed executions

```kusto
traces
| where timestamp > ago(24h)
| where message has '"EventName":"ExecutionFailed"'
| extend payload = parse_json(message)
| project timestamp,
          CorrelationId=tostring(payload.CorrelationId),
          ErrorClass=tostring(payload.ErrorClass),
          Message=tostring(payload.Message)
| order by timestamp desc
```

### Device update failures

```kusto
traces
| where timestamp > ago(24h)
| where message has '"EventName":"DeviceUpdateFailed"'
| extend payload = parse_json(message)
| project timestamp,
          CorrelationId=tostring(payload.CorrelationId),
          SerialNumber=tostring(payload.SerialNumber),
          Reason=tostring(payload.Reason)
| order by timestamp desc
```

## Dry-run procedure

1. Confirm `DRY_RUN=true`.
2. Confirm the inventory version.
3. Confirm the pilot allow-list.
4. Trigger or await execution.
5. Review all `DeviceWouldUpdate` records.
6. Review every validation, eligibility, and correlation failure.
7. Confirm no `DeviceUpdated` event exists.
8. Confirm Autopilot values are unchanged.
9. Record approval or required inventory corrections.

## Write-mode procedure

1. Obtain explicit change approval.
2. Keep the pilot list as small as possible.
3. Enable write mode:

```powershell
.\scripts\Set-DryRun.ps1 `
  -ResourceGroupName '<resource-group>' `
  -FunctionAppName '<function-app>' `
  -DryRun $false `
  -PilotSerialNumbers 'SERIAL001'
```

4. Run one execution.
5. Review `DeviceUpdated` and `DeviceUpdateFailed`.
6. Verify values in Windows Autopilot.
7. Verify dynamic group membership and Intune targeting.
8. Return to dry-run unless the next stage is explicitly approved.

## Pause and resume

Disable the timer:

```powershell
.\scripts\Set-TimerState.ps1 `
  -ResourceGroupName '<resource-group>' `
  -FunctionAppName '<function-app>' `
  -Disabled $true
```

Enable the timer:

```powershell
.\scripts\Set-TimerState.ps1 `
  -ResourceGroupName '<resource-group>' `
  -FunctionAppName '<function-app>' `
  -Disabled $false
```

## Inventory maintenance

1. Retain the current approved file.
2. Validate the proposed new file.
3. Publish with `Publish-Inventory.ps1`.
4. Confirm `INVENTORY_PROVIDER=storage-blob`.
5. Run dry-run and compare the expected delta.
6. Approve before write mode.

## Incident response

### Severity guidance

| Condition | Suggested severity |
|-----------|--------------------|
| Dry-run failure with no production impact | Low |
| Scheduled processing unavailable | Medium |
| Incorrect proposed changes, no writes | Medium |
| Incorrect updates limited to pilot | High |
| Broad unauthorized or unexpected updates | Critical |

### Immediate containment

1. Disable the timer.
2. Set `DRY_RUN=true`.
3. Preserve telemetry and the active inventory.
4. Record the correlation ID and affected serials.
5. Review recent Function configuration and Blob changes.
6. Validate Graph and Azure role assignments.
7. Prepare a reverse inventory if values must be restored.

## Maintenance

- Review Graph and Azure permissions quarterly.
- Review pilot/write-mode settings after every approved change.
- Review telemetry retention and access.
- Update PowerShell, Bicep modules, Actions, and runtime versions through normal
  release review.
- Re-run the complete test suite after behavior or API changes.
- Confirm Microsoft Graph endpoint and permission documentation before major releases.

