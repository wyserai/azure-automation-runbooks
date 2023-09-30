param(
    [Parameter(mandatory=$true)]
    [string] $clientId,

    [Parameter(mandatory=$true)]
    [string] $emailAddress,

    [Parameter(mandatory=$true)]
    [string] $domainName,

    [Parameter(mandatory=$true)]
    [string] $storageAccountResourceGroupName,

    [Parameter(mandatory=$true)]
    [string] $storageAccountName,

    [Parameter(mandatory=$true)]
    [string] $blobContainerName,

    [Parameter(mandatory=$false)]
    [string] $appGatewayResourceGroupName,

    [Parameter(mandatory=$false)]
    [string] $appGatewayName,

    [Parameter(mandatory=$false)]
    [string] $certificateName = "LetsEncrypt",

    [Parameter(mandatory=$false)]
    [string] $keyVaultName
)

# Ensures you do not inherit an AzContext in your runbook
Disable-AzContextAutosave -Scope Process

# Connect to Azure with user-assigned managed identity
Write-Output "Connecting to AzAccount"
$AzureContext = (Connect-AzAccount -Identity -AccountId $clientId)

# Select the appropriate server
Write-Output "Setting server to LetsEncrypt production"
Set-PAServer LE_PROD

# Create new account and order
Write-Output "Creating new account and order for domain $domainName and email address $emailAddress"
New-PAAccount -AcceptTOS -Contact $emailAddress -KeyLength 2048 -Force
New-PAOrder $domainName -Force

# Get authorizations
Write-Output "Retrieving authorizations for HTTP01"
$auths = Get-PAOrder | Get-PAAuthorizations
$authData = $auths | Select @{L='Body';E={Get-KeyAuthorization $_.HTTP01Token (Get-PAAccount)}},
                            @{L='FileName';E={$($_.HTTP01Token)}}

# Set local file path for blob
$filePath = $env:TEMP + "\" + $authData.FileName
Write-Output "Local file path set to $filePath"

# Create acme-challenge file
Write-Output "Writing authData to $filePath"
Set-Content -Value $authData.Body -Path $filePath

# Upload acme-challenge file to blob storage
Write-Output "Connecting to $storageAccountName"
$storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $storageAccountResourceGroupName -Name $storageAccountName
$blobName = ".well-known\acme-challenge\" + $authData.FileName
$blobContext = $storageAccount.Context
Write-Output "Creating blob $blobName in container $blobContainerName"
Set-AzureStorageBlobContent -File $filePath -Container $blobContainerName -Context $blobContext -Blob $blobName -Force

# Send challenge
Write-Output "Sending challenge"
$auths.HTTP01Url | Send-ChallengeAck

# Sane waiting period for challenge
Write-Output "Waiting for challenge validation (60s)"
Start-Sleep -s 60

# Store certificate in variable
Write-Output "Storing certificate with domain $domainName to variable certificateData"
$certificateData = New-PACertificate $domainName

if ($appGatewayName) {
    # Define Application Gateway
    Write-Output "Using App Gateway $appGatewayName"
    $appGateway = Get-AzureRmApplicationGateway -ResourceGroupName $appGatewayResourceGroupName -Name $appGatewayName

    # Retrieve list of current Application Gateway certificates
    $certificateList = $(Get-AzureRmApplicationGatewaySslCertificate -ApplicationGateway $appGateway).Name
    Write-Output "Available certificates on $($appGatewayName): `n $($certificateList)"

    # Check for renewal or new certificate
    if ($certificateList -contains $certificateName) {
        Write-Output "Updating existing certificate $certificateName"
        Set-AzureRmApplicationGatewaySSLCertificate -Name $certificateName -ApplicationGateway $appGateway -CertificateFile $certificateData.PfxFullChain -Password $certificateData.PfxPass
    } else {
        Write-Output "Creating new certificate $certificateName"
        Add-AzureRmApplicationGatewaySslCertificate -ApplicationGateway $appGateway -Name $certificateName -CertificateFile $certificateData.PfxFullChain -Password $certificateData.PfxPass
    }

    # Write configuration back to App Gateway
    Write-Output "Writing updated configuration to $appGatewayName"
    Set-AzureRmApplicationGateway -ApplicationGateway $appGateway
}

if ($keyVaultName) {
    # base64 encode certificate
    $fileContentBytes = get-content $certificateData.PfxFullChain -Encoding Byte
    $fileContentEncoded = [System.Convert]::ToBase64String($fileContentBytes)

    # Write key to Key Vault
    Write-Output "Writing certificate as Secret to Key Vault $keyVaultName"
    $secretValue = ConvertTo-SecureString $fileContentEncoded -AsPlainText -Force
    Set-AzureKeyVaultSecret -VaultName $keyVaultName -Name $certificateName -SecretValue $secretValue
}