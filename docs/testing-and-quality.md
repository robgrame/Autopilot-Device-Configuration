# Testing and Quality

## Quality objectives

- Verify safety behavior without requiring a customer tenant.
- Prevent regressions in exact matching, eligibility, dry-run, and idempotency.
- Validate Graph and Storage retry/error behavior.
- Keep infrastructure and configuration artifacts syntactically valid.
- Require review before release and deployment.

## Test execution

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -Force
.\scripts\Invoke-Tests.ps1
```

The test script writes NUnit-compatible output to `TestResults/Pester.xml`.

## Automated coverage

The Pester suite covers:

- strict Boolean and configuration parsing;
- serial normalization and exact matching;
- missing, duplicate, and ambiguous records;
- Device Name and Group Tag validation;
- duplicate desired Device Names;
- lifecycle, provisioning, join, legacy, exclusion, and conflict eligibility;
- pilot allow-list behavior;
- dry-run and write-mode controls;
- compliant, partial-update, and full-update behavior;
- idempotency;
- Graph pagination, throttling, transient, permanent, and network failures;
- per-device failure isolation;
- package and Blob inventory providers;
- multi-record and empty inventory;
- Blob size and JSON validation;
- Blob URL and SAS rejection;
- Managed Identity token resource and headers;
- Storage REST headers, retries, and HTTP status classification.

The current release has **44 passing tests**.

## Static validation

### PowerShell parser

```powershell
$errors = @()
Get-ChildItem . -Recurse -Include *.ps1,*.psm1 | ForEach-Object {
    $tokens = $null
    $fileErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $_.FullName,
        [ref]$tokens,
        [ref]$fileErrors
    )
    $errors += $fileErrors
}
if ($errors.Count) { $errors }
```

### JSON and Bicep

```powershell
git ls-files '*.json' | ForEach-Object {
    Get-Content -Raw $_ | ConvertFrom-Json | Out-Null
}

az bicep build --stdout --file .\infra\main.bicep | Out-Null
git diff --check
```

## GitHub Actions

`.github/workflows/ci.yml` verifies tests, PowerShell parsing, and Bicep
compilation. CI is a release gate but does not replace customer-tenant dry-run
validation.

## Review gates

1. implementation review;
2. rubber-duck review;
3. security review;
4. remediation;
5. post-fix review;
6. final release review;
7. local validation;
8. commit and push;
9. successful GitHub Actions run;
10. customer-environment validation before deployment or write mode.

## Environment validation

These checks require the authorized customer environment:

- Azure authentication and tenant confirmation;
- subscription and region approval;
- Azure Policy and quota checks;
- Bicep/AZD preview;
- live Managed Identity token acquisition;
- Graph app-role verification;
- dry-run against controlled Autopilot devices;
- write pilot and downstream Intune verification.

## Release checklist

- [ ] `VERSION`, README badge, and `src/package.json` match.
- [ ] Relevant script version headers are current.
- [ ] Documentation reflects behavior and limitations.
- [ ] Tests cover behavior changes and edge cases.
- [ ] Pester, parser, JSON, Bicep, and diff checks pass.
- [ ] No secrets or customer data are committed.
- [ ] Security review has no unresolved findings.
- [ ] GitHub Actions succeeds.
- [ ] Deployment remains dry-run by default.

