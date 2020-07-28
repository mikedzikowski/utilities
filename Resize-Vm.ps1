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
.Parameter ReportPath
    Specifies the path of report output
.NOTES
    CSV fields: Hostname, ResourceGroup, ToBeVmSize, AvailabilitySet (optional)

.EXAMPLE
    . .\Resize-Vm.ps1; Resize-Vm -AvailabilitySetName "AS1"  -ResourceGroup RG1 -NewVmSize Standard_DS3_v2 -ReportPath C:\temp

    . .\Resize-Vm.ps1; Resize-Vm -VmList VM1, VM2 -ResourceGroup RG1 -NewVmSize Standard_DS2_v2 -ReportPath C:\temp

    . .\Resize-Vm -PathToCsv C:\Path.csv -ReportPath C:\temp
#>
[CmdletBinding()]
param
(
    [Parameter(mandatory=$false)]
    [string]
    $PathtoCsv,

    [Parameter(mandatory=$true)]
    [string]
    $ReportPath
)

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

# CSV FileName
$CSVFileName = 'VmResizeReport ' + $(Get-Date -f yyyy-MM-dd) + '.csv'

# Creating DataTable Structure
Write-Verbose 'Creating DataTable Structure'
$DataTable = New-Object System.Data.DataTable
$DataTable.Columns.Add("Hostname","string") | Out-Null
$DataTable.Columns.Add("ResourceGroup","string") | Out-Null
$DataTable.Columns.Add("NewVMSize","string") | Out-Null

#region resize virtual machine not in an availability set
if(!$availabilitySetName -and $VmList)
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

                # Check VM Size after updating
                $vmSize = Get-AzVMSize -ResourceGroupName $resourceGroup -VMName $virtualMachine

                # Append data to CSV File
                $NewRow = $DataTable.NewRow()
                $NewRow.Hostname = $($vm.Name)
                $NewRow.ResourceGroup = $($vm.ResourceGroupName)
                $NewRow.NewVmSize = $($vm.HardwareProfile.VmSize)
                $DataTable.Rows.Add($NewRow)
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
#endregion

#region Resize virtual machines in an availability set
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

                # Append data to CSV File
                $NewRow = $DataTable.NewRow()
                $NewRow.Hostname = $($vm.Name)
                $NewRow.ResourceGroup = $($vm.ResourceGroupName)
                $NewRow.NewVmSize = $($vm.HardwareProfile.VmSize)
                $DataTable.Rows.Add($NewRow)
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
    $DataTable | Export-Csv "$ReportPath\$CSVFileName" -NoTypeInformation -Append -Force
}
#endregion

if($PathtoCsv)
{
    
    # Import extract file data
    $ResizeExtract = Import-Csv -Path $PathtoCsv

    # Find availability sets in csv
    $availabilitySets = $ResizeExtract | Select-Object -Property AvailabilitySet, ResourceGroup, ToBeVmSize -Unique

    #region Resize virtual machines not in an availability set
    foreach($hostname in $ResizeExtract)
    {
        if(!$hostname.AvailabilitySet)
        {
            Resize-Vm -VmList $hostname.hostname -NewVmSize $hostname.ToBeVmSize -ResourceGroup $hostname.ResourceGroup
        }
    }
    #endregion

    #region Resize all machines in an availability set
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
                # Check that all virtual machines listed in csv file are in availability
                if($ResizeExtract.hostname -icontains $vmName)
                {
                    $continue =  $true
                }
                # If machine is found that is not inside csv file stop script
                else
                {
                    $continue = $false
                    Write-Host "Virtual Machine" $Vmname "found in Availability Set" $as.AvailabilitySet "that is not listed in extract file. Stopping script from continuing."
                    exit
                }
            }
            # Continue if all virtual machines are inside csv file
            if($continue -eq $true)
            {
                Write-Host "Verified virtual machines in Availability Set are listed in extract file - continuing with resize of VMS"
                Resize-Vm -AvailabilitySetName $as.AvailabilitySet  -ResourceGroup $as.ResourceGroup -NewVmSize $as.ToBeVmSize
            }
        }
    }
    #endregion
}