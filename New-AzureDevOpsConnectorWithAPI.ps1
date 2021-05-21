[CmdletBinding()]
param
(
    [Parameter(mandatory=$true)]
    [string]
    $OrganizationName,

    [Parameter(mandatory=$true)]
    [string]
    $AzureDevOpsPAT,

    [Parameter(mandatory=$true)]
    [string]
    $ServiceConnectorName,

    [Parameter(mandatory=$true)]
    [string]
    $ServicePrincipalName,

    [Parameter(mandatory=$true)]
    [string]
    $SubscriptionName

)

$AzureDevOpsAuthenicationHeader = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($AzureDevOpsPAT)"))}

$UriOrga = "https://<URL TO ADO INSTANCE>$($OrganizationName)"
$uriAccount = $UriOrga + "_apis/serviceendpoint/endpoints?api-version=5.1-preview.2"

$sp = New-AzADServicePrincipal -DisplayName $ServicePrincipalName -SkipAssignment

$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sp.Secret)
$UnsecureSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

$SubscriptionContext = Get-AzSubscription -SubscriptionName $($SubscriptionName)
$guid = (New-Guid).Guid

$body = '{
    "data": {
        "environment": "AzureUSGovernment",
        "scopeLevel": "Subscription",
        "subscriptionId": "'+ $SubscriptionContext.SubscriptionId +'",
        "subscriptionName": "'+ $SubscriptionName +'",
        "creationMode": "Manual"
    },
    "description": "Service connecctor",
    "id": "'+ $guid + '",
    "name": " '+ $ServiceConnectorName + '",
    "type": "azurerm",
    "url": "https://management.usgovcloudapi.net/",
    "authorization": {
        "parameters": {
            "ServicePrincipalId": "' + $sp.ApplicationId +'",
            "authenticationType": "spnKey",
            "ServicePrincipalKey": " '+ $UnsecureSecret +'",
            "tenantid": "'+ $SubscriptionContext.TenantId +'"
        },
        "scheme": "ServicePrincipal"
    },
    "isShared": false,
    "isReady": true
}'

Invoke-RestMethod -Uri $uriAccount -Method POST -ContentType "application/json" -body $body -Headers $AzureDevOpsAuthenicationHeader -Verbose
