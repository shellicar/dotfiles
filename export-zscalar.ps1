#!/usr/bin/env pwsh

$outputPath = "ZScalerRootCA.pem"

$certificate = Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -like "*ZScaler Root CA*" }

if ($certificate -eq $null) {
    Write-Error "Certificate 'ZScaler Root CA' not found in the Trusted Root Certification Authorities store."
    exit 1
}

$derBytes = $certificate.RawData

$pemHeader = "-----BEGIN CERTIFICATE-----"
$pemFooter = "-----END CERTIFICATE-----"
$pemBody = [System.Convert]::ToBase64String($derBytes, [System.Base64FormattingOptions]::InsertLineBreaks)
$pemContent = "$pemHeader`n$pemBody`n$pemFooter"

Set-Content -Path $outputPath -Value $pemContent -Encoding Ascii
Write-Host "Certificate exported to $outputPath"
