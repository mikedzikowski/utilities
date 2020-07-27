<#.SYNOPSIS
   Simple Script that will resize an array of virtual machines or all virutal machines in an availability set.
.DESCRIPTION
    Simple Script that will resize an array of virtual machines or all virutal machines in an availability set.
    When resizing virtual machines in an Availability Set, this script will verify that all machines listed in CSV match the machines in the Availability Set
    before resizing the machines.
.Parameter ResourceGroup
    Specifies the Resource Group of the virtual machine or availability set
.Parameter VmList
    An array of virtual machine names
.Parameter NewVmSize
    Specifies the Sku size for the virtual machine
.Parameter AvailabilitySetName
    Specifies the availabiltiy set name
.NOTES
<<<<<<< HEAD:Resize-Vm.ps1
    CSV fields: Hostaname, ResourceGroup, ToBe\VmSize, AvailabilitySet (optional)

=======
    CSV fields: Hostaname, ResourceGroup, ToBe\VmSize, AvailabilitySet (optional) 
>>>>>>> 4a5d77c58aacb33c397b0e0fd727b0f7b248f533:Set-NewVmSize.ps1
.EXAMPLE
    . .\Resize-Vm.ps1; Resize-Vm -AvailabilitySetName "AS1"  -ResourceGroup RG1 -NewVmSize Standard_DS3_v2

    . .\Resize-Vm.ps1; Resize-Vm -VmList VM1, VM2 -ResourceGroup RG1 -NewVmSize Standard_DS2_v2

    . .\Resize-Vm -PathToCsv C:\Path.csv
#>
[CmdletBinding()]
param
(
    [Parameter(mandatory=$false)]
    [string]
    $PathtoCsv
)
if($PathtoCsv)
{
    $ResizeExtract = Import-Csv -Path $PathtoCsv

    $availabilitySets = $ResizeExtract | Select-Object -Property AvailabilitySet, ResourceGroup, ToBeVmSize -Unique

    foreach($hostname in $ResizeExtract)
    {
        if(!$hostname.AvailabilitySet)
        {
            Resize-Vm -VmList $hostname.hostname -NewVmSize $hostname.ToBeVmSize -ResourceGroup $hostname.ResourceGroup
        }
    }
    foreach ($as in $availabilitySets)
    {
        If($as.AvailabilitySet -ne "" -or $null)
        {
            $availabilitySet = Get-AzAvailabilitySet -Name $as.AvailabilitySet
            $vmIds = $availabilitySet.VirtualMachinesReferences
                foreach ($vmid in $vmIds)
                {
                    $string = $vmID.Id.Split("/")
                    $vmName = $string[8]

                if($ResizeExtract.hostname -icontains $vmName)
                {
                    $continue =  $true
                }
                else
                {
                    $continue = $false
                    Write-Output "Virtual Machine" $Vmname "found in Availability Set" $as.AvailabilitySet "that is not listed in extract file. Stopping script from continuing."
                    exit
                }
            }
            if($continue -eq $true)
            {
                Write-Output "Verified virtual machines in Availability Set are listed in extract file - continuing with resize of VMS"
                Resize-Vm -AvailabilitySetName $as.AvailabilitySet  -ResourceGroup $as.ResourceGroup -NewVmSize $as.ToBeVmSize
            }
        }
    }
}
Function Resize-Vm {

[CmdletBinding()]
param
(
    [Parameter(mandatory=$true, ParametersetName = 'AvailabilitySet')]
    [Parameter(mandatory=$true, ParametersetName = 'VirtualMachine')]
    [string]
    $ResourceGroup,

    [Parameter(mandatory=$false, ParametersetName = 'AvailabilitySet')]
    [Parameter(mandatory=$true, ParametersetName = 'VirtualMachine')]
    [array]
    $VmList,

    [Parameter(mandatory=$true, ParametersetName = 'AvailabilitySet')]
    [Parameter(mandatory=$true, ParametersetName = 'VirtualMachine')]
    [string]
    $NewVmSize,

    [Parameter(mandatory=$true, ParametersetName = 'AvailabilitySet')]
    [Parameter(mandatory=$false,ParametersetName = 'VirtualMachine')]
    $AvailabilitySetName
)
$ErrorActionPreference = "SilentlyContinue"

if(!$availabilitySetName)
{
    foreach($virtualMachine in $vmList)
    {

        $vmSize = Get-AzVMSize -ResourceGroupName $resourceGroup -VMName $virtualMachine  | Out-Null
        $vm = Get-AzVM -ResourceGroupName $resourceGroup -VMName $virtualMachine | Out-Null

    if($vmSize.name -contains $newVmSize)
    {
        Write-Output '----------------------------------------------------------------------------------------'
        Write-Output 'Sku for resize found on hardware cluster' $($vm.AvailabilitySetReference.id)
        Write-Output '----------------------------------------------------------------------------------------'

            If($vm.HardwareProfile.VmSize -ne $NewVmSize)
            {
                $vm.HardwareProfile.VmSize = $newVmSize

                Write-Output '----------------------------------------------------------------------------------------'
                Write-Output 'Resizing Virtual Machine' $vm.Name "to Sku size" $newVmSize
                Write-Output '----------------------------------------------------------------------------------------'

                $job = Update-AzVM -VM $vm -ResourceGroupName $resourceGroup -Verbose -AsJob

                do{
                    $status = Get-Job -id $job.Id
                    Write-Output "Resizing" $vm.Name
                    Start-Sleep 5
                } while ($status.State -eq "Running")

                Write-Output '----------------------------------------------------------------------------------------'
                Write-Output 'Resize of Virtual Machine' $vm.Name "is" $job.State
                Write-Output '----------------------------------------------------------------------------------------'
            }
            else
            {
                Write-Output '----------------------------------------------------------------------------------------'
                Write-Output 'Virtual Machine' $virtualMachine "is already sized at" $NewVmSize
                Write-Output '----------------------------------------------------------------------------------------'
            }
        }
    }
}
else
{
    $availabilitySetShutdown = Get-AzAvailabilitySet -Name $availabilitySetName
    $vmIds = $availabilitySetShutdown.VirtualMachinesReferences

    Write-Output '----------------------------------------------------------------------------------------'
    Write-Output 'Shutting down all virtual machines in availabiliy set:' $($availabilitySetShutdown.Name)
    Write-Output '----------------------------------------------------------------------------------------'

    foreach ($vmId in $vmIds)
    {
        $string = $vmId.Id.Split("/")
        $vmName = $string[8]
        $stopVmJob = Stop-AzVM -ResourceGroupName $resourceGroup -Name $vmName -Force -AsJob

        do{
            $status = Get-Job -id $stopVmJob.Id
            Write-Output "Stopping" $vmName
            Start-Sleep 5
        } while ($status.State -eq "Running")
    }

    foreach ($vmId in $vmIDs)
    {
        $string = $vmID.Id.Split("/")
        $vmName = $string[8]
        $vm = Get-AzVM -ResourceGroupName $resourceGroup -Name $vmName

            If($vm.HardwareProfile.VmSize -ne $NewVmSize)
            {
                Write-Output '----------------------------------------------------------------------------------------'
                Write-Output 'Virtual Machine' $vmName 'is being resized to' $newVmSize
                Write-Output '----------------------------------------------------------------------------------------'

                $vm.HardwareProfile.VmSize = $NewVmSize

                $updateVmJob = Update-AzVM -ResourceGroupName $resourceGroup -VM $vm -AsJob

                do{
                    $status = Get-Job -id $updateVmJob.Id
                    Write-Output "Resizing VM:" $vmName "to" $newVmSize
                    Start-Sleep 5
                } while ($status.State -eq "Running")

                $startVmJob = Start-AzVM -ResourceGroupName $resourceGroup -Name $vmName -AsJob

                do{
                    $status = Get-Job -id $startVmJob.Id
                    Write-Output "Starting VM:" $vmName
                    Start-Sleep 5
                } while ($status.State -eq "Running")
            }
            else
            {
                Write-Output '----------------------------------------------------------------------------------------'
                Write-Output 'Virtual Machine' $vm.name 'is already right sized to' $newVmSize
                Write-Output '----------------------------------------------------------------------------------------'

                $startVmJob = Start-AzVM -ResourceGroupName $resourceGroup -Name $vmName -AsJob

                do{
                    $status = Get-Job -id $startVmJob.Id
                    Write-Output "Starting VM:" $vm.Name
                    Start-Sleep 5
                } while ($status.State -eq "Running")
            }
        }
    }
}