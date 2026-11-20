#requires -Version 5.1
<#
.SYNOPSIS
  Lance la validation statique d'un package Chocolatey et retourne un code de sortie.
.EXAMPLE
  .\Verifier-Paquet.ps1 -PackagePath 'C:\Packages\example.1.0.0.nupkg'
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$PackagePath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Validateur-Paquet.ps1')

$result = Test-CMILPackage -Path $PackagePath
$result | Format-List IsValid, Id, Version, Status | Out-Host
if ($result.Issues.Count -gt 0) {
    $result.Issues | Format-Table Level, Code, Message -AutoSize -Wrap | Out-Host
}
if (-not $result.IsValid) { exit 1 }
