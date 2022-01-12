# Get the connection "AzureRunAsConnection"
$connectionName = "AzureRunAsConnection"

# Import Variable Assets 
$expiration = Get-AutomationVariable -Name 'expiration'

# Connect to Azure (Azure US Government) 
$servicePrincipalConnection = Get-AutomationConnection -Name $connectionName   

try 
{
        Login-AzureRmAccount `
        -EnvironmentName AzureUSGovernment `
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
$subscriptions = Get-AzureRmSubscription -SubscriptionName "<SUBSCRIPTION>"

$resourceGroups = Get-AzureRmResourceGroup 

# Find Resource Group in Subscription 
If($resourceGroups)
{
    foreach($resourceGroup in $resourceGroups)
    {            
        $certificates = Get-AzureRMWebAppCertificate -ResourceGroupName $resourceGroup.ResourceGroupName

        foreach($certificate in $certificates)
        {
            #Write-Host $certificate.FriendlyName 

            [datetime]$expiration = $($certificate.ExpirationDate)
            [int]$certificateExpiration = ($expiration - $(get-date)).Days
    
            if ($certificateExpiration -lt 30)
            {
                Write-Output "Warning subscription $($subscription.Name)contains certificate named $($certificate.FriendlyName) that expires under 30 days on $($certificate.ExpirationDate) in: $certificateExpiration days"
            }
        }
    }
}