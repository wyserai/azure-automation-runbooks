# Azure Automation Runbooks

## LetsEncrypt

Azure Automation Runbook to renew LetsEncrypt certificates on Azure Application Gateway / Azure Key Vault

*Note, requires Posh-ACME automation module*

## Parameters
```PowerShell
[string] $clientId                         # User-assigned managed identity ClientId
[string] $emailAddress                     # Email address for renewals
[string] $domainName                       # Domain name to request the certificate for (i.e.: test.contoso.com)
[string] $storageAccountResourceGroupName  # Resource Group name in which the Storage Account resides
[string] $storageAccountName               # Storage Account name
[string] $blobContainerName                # Name of the blob container
```

### Optional For Updating Azure Application Gateway
```PowerShell
[string] $appGatewayName                   # If set, will use Application Gateway name
[string] $appGatewayResourceGroupName      # Resource Group name in which the Application Gateway resides
[string] $certificateName                  # Desired name of the certificate or name of the existing certificate
```

### Optional For Updating Azure Key Vault
```PowerShell
[string] $keyVaultName                     # If set, will use Azure Key Vault to store certificate
[string] $certificateName                  # Desired name of the certificate or name of the existing certificate
```

LetsEncrypt advises that you set the renewals to monthly recurring.