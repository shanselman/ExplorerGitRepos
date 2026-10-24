[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $Root = 'C:\github'
)

$ErrorActionPreference = 'Stop'
$registryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\PerFolderRoots'
$nativePath = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\PerFolderRoots'
$folderType = '{69F1E26B-EC64-4280-BC83-F1EB887EC35A}'
$provider = '{1212F95B-257E-414E-B44F-F26634BD2627}'
$appId = 'windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel'

$existingPaths = @()
if (Test-Path -LiteralPath $registryPath) {
    $existingPaths = @(Get-ChildItem -LiteralPath $registryPath |
        ForEach-Object { (Get-ItemProperty -LiteralPath $_.PSPath).Path })
}

$repositories = @(Get-ChildItem -LiteralPath $Root -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName '.git') } |
    Sort-Object FullName)
$pending = @($repositories | Where-Object { $_.FullName -notin $existingPaths })

Write-Output "Found $($repositories.Count) repositories; $($pending.Count) need registration."
if ($pending.Count -eq 0) {
    return
}

if (-not $PSCmdlet.ShouldProcess($registryPath, "Register $($pending.Count) repositories from $Root")) {
    $pending | Select-Object -ExpandProperty FullName
    return
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
if (Test-Path -LiteralPath $registryPath) {
    $backup = Join-Path $PSScriptRoot "PerFolderRoots-before-$timestamp.reg"
    & reg.exe export $nativePath $backup /y
    if ($LASTEXITCODE -ne 0) {
        throw "Registry export failed; no registrations were changed."
    }
    Write-Output "Existing registry entries backed up to: $backup"
}

$registrations = @($pending | ForEach-Object {
    [pscustomobject]@{
        Key = Join-Path $registryPath ([guid]::NewGuid().ToString('B').ToUpperInvariant())
        Path = $_.FullName
    }
})
# Keep the exact new key names so additions can be removed independently.
$manifest = Join-Path $PSScriptRoot "PerFolderRoots-added-$timestamp.clixml"
$registrations | Export-Clixml -LiteralPath $manifest
Write-Output "New registration manifest: $manifest"

foreach ($entry in $registrations) {
    New-Item -Path $entry.Key -ErrorAction Stop | Out-Null
    $values = @{
        FolderType = $folderType
        PropertyProvider = $provider
        RegisteredAppID = $appId
        Path = $entry.Path
    }
    foreach ($name in $values.Keys) {
        New-ItemProperty -LiteralPath $entry.Key -Name $name -Value $values[$name] -PropertyType String | Out-Null
    }
    $saved = Get-ItemProperty -LiteralPath $entry.Key
    foreach ($name in $values.Keys) {
        if ($saved.$name -cne $values[$name]) {
            throw "Registry verification failed for $($entry.Key): $name"
        }
    }
    Write-Output "Registered: $($entry.Path)"
}
