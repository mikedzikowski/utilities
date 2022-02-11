<#
    .SYNOPSIS
        This script will create an AD group if it is not found in Azure AD.
        Once the Azure AD group is found or created a a single user or an array of users wil be added to the AD Group.

    .PARAMETER AdGroupName
        The Azure AD Group Name.

    .PARAMETER AdRoleDefinitionName
        The role definition in Azure.

    .PARAMETER UsersToAdd
        An array of user to add to the Azure AD Group.
#>

param
(
    [parameter(Mandatory)]
    [string]
    $AdGroupName,

    [parameter(Mandatory)]
    [string]
    $AdRoleDefinitionName,

    [parameter(Mandatory)]
    [array]
    $UsersToAdd
)

# Checking if group is already created in Azure AD
Write-host "Checking for the following Azure AD group:" $AdGroupName

# $group will be the AD group used for AKSAdmins in LED - we will write the group id to a dynamic variable
$group = Get-AzADGroup -DisplayName $AdGroupName -Verbose

if(!$group)
{
    $group = New-AzADGroup -DisplayName $AdGroupName -MailNickname $AdGroupName

    # Waiting to ensure AD Group is created and replicated
    Start-Sleep 60

    if($group)
    {
        $roleAssignment = Get-AzRoleAssignment -RoleDefinitionName "$AdRoleDefinitionName" | Where-Object {$_.DisplayName -eq $AdGroupName}

        if(!$roleAssignment)
        {
            $roleAssignment = New-AzRoleAssignment -ObjectId $group.id -RoleDefinitionName $role.Name -Verbose

            Write-Host "The following role assignment was created:" $AdGroupName "was assigned to" $AdRoleDefinitionName
        }
        else
        {
            Write-Host "The following role assignment was already defined:" $AdGroupName "is assigned to" $AdRoleDefinitionName
        }
    }
}
else
{
    # Group already exisit - checking for role assignment
    $roleAssignment = Get-AzRoleAssignment -RoleDefinitionName "$AdRoleDefinitionName" | Where-Object {$_.DisplayName -eq $AdGroupName}

    # If role definition is found add the role assignment to the AD group
    if(!$roleAssignment)
    {
        $roleAssignment = New-AzRoleAssignment -ObjectId $group.id -RoleDefinitionName "$AdRoleDefinitionName" -Verbose

        Write-Host "The following role assignment was created:" $AdGroupName "was assigned to" $AdRoleDefinitionName
    }
    else
    {
        Write-Host "The following role assignment was already defined:" $AdGroupName "is assigned to" $AdRoleDefinitionName
    }
}
# If role was assigned to the AD group, populate group with members
if($roleAssignment)
{
    foreach($user in $UsersToAdd)
    {
        $adUser = Get-AzADUser -UserPrincipalName $user

        Write-host "Checking" $user "for existing group membership in the following Azure AD Group:" $AdGroupName

        $checkAdGroup = Get-AzADGroupMember -GroupObjectId $group.Id | Where-Object {$_.UserPrincipalName -eq $adUser.UserPrincipalName}

        if(!$checkAdGroup)
        {
            add-AzADGroupMember -MemberObjectId $adUser.id -TargetGroupObjectId $group.id -Verbose

            Write-host "The user" $user "was added to the following Azure AD Grouo" $AdGroupName
        }
        else
        {
            Write-host "The user" $user "was already found in the following Azure AD group:" $AdGroupName
        }
    }
}
else
{
    Write-host "Please verify role assignment was created successfully"
    exit 1
}

Write-Host $group.id

