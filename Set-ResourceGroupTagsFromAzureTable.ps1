<#.SYNOPSIS
  
.DESCRIPTION
    A simple script that utilizes an Azure table to retrieve tags values and set them on each matching resource group.

    Requires PowerShell module AzTable.

    To install run Install-Module AzTable.

.PARAMETER StorageAccountResourceGroupName

    Resource group name where the storage account resides that contains the Azure table storage account

.PARAMETER StorageAccountName

    Storage account name where Azure table storage account resides

.PARAMETER TableName

    Name of table where the tag data is located

.NOTES
    Update tag hashtable to fit organizational requirements to include tag values required.
    Tags must be included in Azure Table. For example:

    ResourceGroup  : Demo
    Owner          : test@example.com
    Department     : HumanResources
    PartitionKey   : ResourceGroup1
    RowKey         : Demo
    TableTimestamp : 2/3/2021 3:55:55 PM -05:00
    Etag           : W/"datetime'2021-02-03T20%3A55%3A55.9723037Z'"

.Example
.\Set-ResourceGroupTags.ps1 -StorageAccountResourceGroupName RG1 -StorageAccountName StorageAccount1 -TableName Table1
    
#>

[CmdletBinding()]
param
(
    [Parameter(mandatory=$true)]
    [string]
    $StorageAccountResourceGroupName,

    [Parameter(mandatory=$true)]
    [string]
    $StorageAccountName,

    [Parameter(mandatory=$true)]
    [string]
    $TableName
)

# Find resource groups in subscription
$resourceGroupNames = (Get-AzResourceGroup).ResourceGroupName

# Set storage account context
$ctx = (Get-AzStorageAccount -ResourceGroupName $StorageAccountResourceGroupName -Name $StorageAccountName).Context

# Set close table
$tagTable = (Get-AzStorageTable –Name $TableName –Context $ctx).CloudTable

# Create tags object from Azure Table
$tags = Get-AzTableRow -Table $tagTable

foreach($resourceGroupName in $resourceGroupNames)
{
    foreach($tag in $tags)
    {
        try
        {
            if($tag.resourceGroup -eq $resourceGroupName)
            {
                Set-AzResourceGroup -Name $resourceGroupName -Tag @{Owner=$tag.Owner; Department=$tag.Department}
            }
            else
            {
                Write-Host "Resource group not found in Azure Table Please Review"
            }
        }
        catch
        {
            throw "Please review - exeception found"
        }
    }
}
