$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function ConvertTo-NativeValue {
    param([AllowNull()] $Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [pscustomobject]) {
        $result = @{}
        foreach ($property in $Value.PSObject.Properties) {
            $result[$property.Name] = ConvertTo-NativeValue $property.Value
        }
        return $result
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string] -and $Value -isnot [hashtable]) {
        return @($Value | ForEach-Object { ConvertTo-NativeValue $_ })
    }
    return $Value
}

function ConvertFrom-EnvironmentValue {
    param([Parameter(Mandatory)][string] $Value)

    $trimmed = $Value.Trim()
    if ($trimmed -match '^(true|false|null|-?\d+(\.\d+)?|\[|\{|")') {
        try { return ConvertTo-NativeValue ($trimmed | ConvertFrom-Json) } catch { }
    }
    return $Value
}

function Merge-Parameters {
    param([hashtable] $Target, [AllowNull()] $Source)
    if ($null -eq $Source) { return }
    foreach ($property in $Source.PSObject.Properties) {
        $Target[$property.Name] = ConvertTo-NativeValue $property.Value
    }
}

$configDirectory = [System.IO.Path]::GetFullPath('C:\bootstrap\config')
foreach ($variableName in 'BCC_CONFIG_FILE', 'BCC_PARAMETERS_FILE') {
    $configuredPath = [Environment]::GetEnvironmentVariable($variableName)
    if ($configuredPath) {
        $fullPath = [System.IO.Path]::GetFullPath($configuredPath)
        if ([System.IO.Path]::GetDirectoryName($fullPath) -ne $configDirectory) {
            throw "$variableName must name a file directly inside $configDirectory."
        }
    }
}

$parameters = @{}

if ($env:BCC_PARAMETERS_FILE -and (Test-Path -LiteralPath $env:BCC_PARAMETERS_FILE)) {
    Merge-Parameters $parameters (Get-Content -LiteralPath $env:BCC_PARAMETERS_FILE -Raw | ConvertFrom-Json)
}
if ($env:BCC_PARAMETERS_JSON) {
    Merge-Parameters $parameters ($env:BCC_PARAMETERS_JSON | ConvertFrom-Json)
}

Get-ChildItem Env: | Where-Object Name -like 'BCC_PARAM_*' | ForEach-Object {
    $name = $_.Name.Substring('BCC_PARAM_'.Length)
    $parameters[$name] = ConvertFrom-EnvironmentValue $_.Value
}

if ($parameters.ContainsKey('Credential')) {
    $credentialValue = $parameters['Credential']
    if ($credentialValue -is [hashtable]) {
        $username = [string]$credentialValue['username']
        $password = [string]$credentialValue['password']
        $parameters['Credential'] = [pscredential]::new(
            $username,
            (ConvertTo-SecureString $password -AsPlainText -Force)
        )
    }
} elseif ($env:BCC_CREDENTIAL_USERNAME -and $env:BCC_CREDENTIAL_PASSWORD) {
    $parameters['Credential'] = [pscredential]::new(
        $env:BCC_CREDENTIAL_USERNAME,
        (ConvertTo-SecureString $env:BCC_CREDENTIAL_PASSWORD -AsPlainText -Force)
    )
}

$commandName = if ($env:BCC_COMMAND) { $env:BCC_COMMAND } else { 'New-BcContainer' }
docker info *> $null
if ($LASTEXITCODE -ne 0) {
    throw 'Cannot reach the host Docker engine through \\.\pipe\docker_engine.'
}
if ($env:BCC_CONFIG_FILE) {
    if (-not (Test-Path -LiteralPath $env:BCC_CONFIG_FILE)) {
        throw "BcContainerHelper config file not found: $($env:BCC_CONFIG_FILE)"
    }
    $canonicalConfigFile = 'C:\ProgramData\BcContainerHelper\BcContainerHelper.config.json'
    if ($env:BCC_CONFIG_FILE -ne $canonicalConfigFile) {
        Copy-Item -LiteralPath $env:BCC_CONFIG_FILE -Destination $canonicalConfigFile -Force
    }
}
Import-Module BcContainerHelper

# Resolve a moving BC artifact at run time. Format: latest:<type>:<country>
if ($parameters.ContainsKey('artifactUrl') -and
    $parameters['artifactUrl'] -is [string] -and
    $parameters['artifactUrl'] -like 'latest:*') {
    $artifactSelector = $parameters['artifactUrl'].Split(':')
    if ($artifactSelector.Count -ne 3) {
        throw "Invalid artifact selector '$($parameters['artifactUrl'])'. Expected latest:<type>:<country>."
    }
    $parameters['artifactUrl'] = Get-BcArtifactUrl `
        -type $artifactSelector[1] `
        -country $artifactSelector[2] `
        -select Latest
    if (-not $parameters['artifactUrl']) {
        throw "No latest $($artifactSelector[1]) artifact was found for country $($artifactSelector[2])."
    }
    Write-Host "Resolved artifact URL: $($parameters['artifactUrl'])"
}

$command = Get-Command -Name $commandName -ErrorAction Stop
$unknown = @($parameters.Keys | Where-Object { -not $command.Parameters.ContainsKey($_) })
if ($unknown.Count -gt 0) {
    throw "Unknown parameter(s) for ${commandName}: $($unknown -join ', ')"
}

Write-Host "Executing $commandName with $($parameters.Count) parameter(s): $($parameters.Keys -join ', ')"
if ($env:BCC_DRY_RUN -eq 'true') {
    Write-Host 'Dry run requested; no BcContainerHelper command was executed.'
    exit 0
}

& $commandName @parameters
