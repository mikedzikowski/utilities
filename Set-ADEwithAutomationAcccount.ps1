# script based on work found here: https://github.com/Azure/Azure-Security-Center/blob/master/Remediation%20scripts/Disk%20encryption%20should%20be%20applied%20on%20virtual%20machines/Powershell/Enable-AzureVMDiskEncryption.ps1

<#.SYNOPSIS
        Simple Script that can be used with an Azure Automation Account to upate ADE settings.
.DESCRIPTION
        Simple Script that can be used with an Azure Automation Account to upate ADE settings.
.Parameter Keyvault
	Specifies the Vault name where key will be set.
.Parameter CloudEnvironment
 	Specifies the cloud (i.e. AzureCloud vs AzureUSGovernment).  
.NOTES
    	script based on work found here: https://github.com/Azure/Azure-Security-Center/blob/master/Remediation%20scripts/Disk%20encryption%20should%20be%20applied%20on%20virtual%20machines/Powershell/Enable-AzureVMDiskEncryption.ps1
    
    	The following modules must be imported into the Azure Automation environment
    
	Azure
	Az.Accounts
	Az.Security
	Az.Compute
	Az.KeyVault
#>


Import-Module Azure
Import-Module Az.Accounts
Import-Module Az.Security
Import-Module Az.Compute
Import-Module Az.KeyVault

[CmdletBinding()]
param
(
    [Parameter(mandatory=$true)]
    [string]
    $Keyvault,
    
    [Parameter(mandatory=$true)]
    [string]
    $CloudEnvironment
)

# Get the connection "AzureRunAsConnection"
$connectionName = "AzureRunAsConnection"

# Connect to Azure (Azure US Government) 
$servicePrincipalConnection = Get-AutomationConnection -Name $connectionName   

try 
{
        Connect-AzAccount `
        -EnvironmentName $CloudEnvironment `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint | Out-Null
}
catch
{
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $ConnectionName not found."
        throw $ErrorMessage
    }
    else
    {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}
# Find Subscription 
$subscriptions = Get-AzSubscription -SubscriptionName "demosub"

# Loop Through Subs
foreach($Subscription in $Subscriptions)
{
    $Id = ($Subscription.Id)
    Select-AzSubscription $Id
    # Get Security Task for Storage Security
    $SecurityTasks += Get-AzSecurityTask | Where-Object {$_.RecommendationType -eq "EncryptionOnVm"} 
    write-host "$securityTasks"
}
write-host "$securityTasks"

foreach($SecurityTask in $SecurityTasks)
{
    $sub = $securityTask.Id.Split("/")[2]
    $vm = $securityTask.ResourceId.Split("/")[8]
    $vmlocation = (Get-AzVm -Name $vm).Location
    $vmrg = (Get-AzVm -Name $vm).ResourceGroupName
    Select-AzSubscription $sub

    # Check for Existing Keyvault
    [array]$vaultnames = $keyvault
    [array]$localvault = $null
    $vaultnames += (Get-AzKeyVault).VaultName
    foreach ($vaultname in $vaultnames)
    {
        $vaultdetails = Get-AzKeyVault -VaultName $vaultname
        
        # Find local KVs with Disk Encryption Flag
        if(($vaultdetails.EnabledForDiskEncryption -eq $true) -and ($vmlocation -eq $vaultdetails.Location))
        {
        $localvault += $vaultdetails.VaultName
        }
    }
        
    # Use local KV if one exists
    if ($localvault -ne $null)
    {
        $localvaultdetails = Get-AzKeyVault -VaultName $localvault[0]

        write-host $localvaultdetails

        # Encrypt VM using existing KV 
        Set-AzVMDiskEncryptionExtension -ResourceGroupName $vmrg -VMName $vm -DiskEncryptionKeyVaultUrl $localvaultdetails.VaultUri -DiskEncryptionKeyVaultId $localvaultdetails.ResourceId -VolumeType All -SkipVmBackup -Force
    } 

    # If no local KV exists, create one.
    else 
    {
        # Create KV with unique name, allowing for long location names
        $subid = $sub.split("-")[0].substring(0,4)
        $vaultname = "${vmlocation}${subid}"
        $vaultRG = "DiskEncryptionRG-${vmlocation}"
        New-AzResourceGroup –Name $vaultRG –Location $vmlocation
        New-AzKeyVault -VaultName $vaultname -ResourceGroupName $vaultRG -Location $vmlocation -EnableSoftDelete -EnabledForDeployment -EnabledForTemplateDeployment -EnabledForDiskEncryption
        $kvid = (Get-AzKeyVault -VaultName $vaultname -ResourceGroupName $vaultRG).ResourceId
        $kvurl = (Get-AzKeyVault -VaultName $vaultname -ResourceGroupName $vaultRG).VaultUri

        # Encrypt VM
        $encryptStatus = Set-AzVMDiskEncryptionExtension -ResourceGroupName $vmrg -VMName $vm -DiskEncryptionKeyVaultUrl $kvurl -DiskEncryptionKeyVaultId $kvid -VolumeType All -SkipVmBackup -Force 
        Write-Output $encryptStatus
    }
}
