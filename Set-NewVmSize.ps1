<#.SYNOPSIS
   Simple Script that will resize an array of virtual machines or all virutal machines in an availability set. 
.DESCRIPTION
    Simple Script that will resize an array of virtual machines or all virutal machines in an availability set. 
.Parameter ResourceGroup
    Specifies the Resource Group of the virtual machine or availability set
.Parameter VmList
    An array of virtual machine names
.Parameter NewVmSize
    Specifies the Sku size for the virtual machine
.Parameter AvailabilitySetName
    Specifies the availabiltiy set name
.NOTES
    CSV fields: Hostaname, ResourceGroup, ToBe\VmSize, AvailabilitySet (optional) 
    
.EXAMPLE
    . .\Set-NewVmSize.ps1; Set-NewVMsize -AvailabilitySetName "AS1"  -ResourceGroup RG1 -NewVmSize Standard_DS3_v2
    
    . .\Set-NewVmSize.ps1; Set-NewVMsize -VmList VM1, VM2 -ResourceGroup RG1 -NewVmSize Standard_DS2_v2

    . .\Set-NewVMsize -PathToCsv C:\Path.csv
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
            Set-NewVmSize -VmList $hostname.hostname -NewVmSize $hostname.ToBeVmSize -ResourceGroup $hostname.ResourceGroup
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
                    Write-host "Virtual Machine" $Vmname "found in Availability Set" $as.AvailabilitySet "that is not listed in extract file. Stopping script from continuing."
                    break 
                }
            }
            if($continue -eq $true)
            {
                Write-host "Verified virtual machines in Availability Set are listed in extract file - continuing with resize of VMS"
                Set-NewVMsize -AvailabilitySetName $as.AvailabilitySet  -ResourceGroup $as.ResourceGroup -NewVmSize $as.ToBeVmSize
            }
        }
    }
}
Function Set-NewVmsize {

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

if(!$availabilitySetName)
{
    foreach($virtualMachine in $vmList)
    {
        $vmSize = Get-AzVMSize -ResourceGroupName $resourceGroup -VMName $virtualMachine

        $vm = Get-AzVM -ResourceGroupName $resourceGroup -VMName $virtualMachine 
    
    if($vmSize.name -contains $newVmSize)
    {
        Write-Host '----------------------------------------------------------------------------------------' 
        Write-Host 'Sku for resize found on hardware cluster' $($vm.AvailabilitySetReference.id)
        Write-Host '----------------------------------------------------------------------------------------' 

            If($vm.HardwareProfile.VmSize -ne $NewVmSize)
            {
                $vm.HardwareProfile.VmSize = $newVmSize

                Write-Host '----------------------------------------------------------------------------------------' 
                Write-Host 'Resizing Virtual Machine' $vm.Name "to Sku size" $newVmSize
                Write-Host '----------------------------------------------------------------------------------------' 

                $job = Update-AzVM -VM $vm -ResourceGroupName $resourceGroup -Verbose -AsJob 

                do{
                    $status = Get-Job -id $job.Id
                    Write-Host "Resizing" $vm.Name 
                    Start-Sleep 5
                } while ($status.State -eq "Running")

                Write-Host '----------------------------------------------------------------------------------------' 
                Write-Host 'Resize of Virtual Machine' $vm.Name "is" $job.State
                Write-Host '----------------------------------------------------------------------------------------' 
            }
            else 
            {
                Write-Host '----------------------------------------------------------------------------------------' 
                Write-Host 'Virtual Machine' $virtualMachine "is already sized at" $NewVmSize
                Write-Host '----------------------------------------------------------------------------------------' 
            }
        }
    }
}
else
{
    $availabilitySetShutdown = Get-AzAvailabilitySet -Name $availabilitySetName
    $vmIds = $availabilitySetShutdown.VirtualMachinesReferences   

    Write-Host '----------------------------------------------------------------------------------------' 
    Write-Host 'Shutting down all virtual machines in availabiliy set:' $($availabilitySetShutdown.Name)
    Write-Host '----------------------------------------------------------------------------------------' 

    foreach ($vmId in $vmIds)
    {
        $string = $vmId.Id.Split("/")
        $vmName = $string[8]
        $stopVmJob = Stop-AzVM -ResourceGroupName $resourceGroup -Name $vmName -Force -AsJob

        do{
            $status = Get-Job -id $stopVmJob.Id
            Write-Host "Stopping" $vmName
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
                Write-Host '----------------------------------------------------------------------------------------' 
                Write-Host 'Virtual Machine' $vmName 'is being resized to' $newVmSize
                Write-Host '----------------------------------------------------------------------------------------' 

                $vm.HardwareProfile.VmSize = $NewVmSize

                $updateVmJob = Update-AzVM -ResourceGroupName $resourceGroup -VM $vm -AsJob

                do{
                    $status = Get-Job -id $updateVmJob.Id
                    Write-Host "Resizing VM:" $vmName "to" $newVmSize
                    Start-Sleep 5
                } while ($status.State -eq "Running")

                $startVmJob = Start-AzVM -ResourceGroupName $resourceGroup -Name $vmName -AsJob

                do{
                    $status = Get-Job -id $startVmJob.Id
                    Write-Host "Starting VM:" $vmName
                    Start-Sleep 5
                } while ($status.State -eq "Running")
            }
            else
            {
                Write-Host '----------------------------------------------------------------------------------------' 
                Write-Host 'Virtual Machine' $vm.name 'is already right sized to' $newVmSize
                Write-Host '----------------------------------------------------------------------------------------' 

                $startVmJob = Start-AzVM -ResourceGroupName $resourceGroup -Name $vmName -AsJob

                do{
                    $status = Get-Job -id $startVmJob.Id
                    Write-Host "Starting VM:" $vm.Name
                    Start-Sleep 5
                } while ($status.State -eq "Running")
            }
        }
    }
}