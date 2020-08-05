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
.Parameter FileName
    Specifies the filename appended to .csv file. Example when using "TestFile": TestFile_VmResizeReport_2020-01-01.csv
.NOTES
    CSV fields: Hostname, ResourceGroup, ToBeVmSize, AvailabilitySet (optional)

.EXAMPLE
    . .\Resize-Vm.ps1; Resize-Vm -AvailabilitySetName "AS1"  -ResourceGroup RG1 -NewVmSize Standard_DS3_v2 -ReportPath C:\temp -FileName "TestFile"

    . .\Resize-Vm.ps1; Resize-Vm -VmList VM1, VM2 -ResourceGroup RG1 -NewVmSize Standard_DS2_v2 -ReportPath C:\temp -FileName "TestFile"

    . .\Resize-Vm -PathToCsv C:\Path.csv -ReportPath C:\temp -FileName "TestFile"
#>
[CmdletBinding()]
param
(
    [Parameter(mandatory=$false)]
    [string]
    $PathtoCsv,

    [Parameter(mandatory=$false)]
    [string]
    $ReportPath,

    [Parameter(mandatory=$false)]
    [string]
    $Filename

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

    [Parameter(mandatory=$false, ParametersetName = 'AvailabilitySet')]
    [Parameter(mandatory=$true, ParametersetName = 'VirtualMachine')]
    [string]
    $NewVmSize,

    [Parameter(mandatory=$true, ParametersetName = 'AvailabilitySet')]
    [Parameter(mandatory=$false,ParametersetName = 'VirtualMachine')]
    $AvailabilitySetName,

    [Parameter(mandatory=$true, ParametersetName = 'AvailabilitySet')]
    [Parameter(mandatory=$true, ParametersetName = 'VirtualMachine')]
    [string]
    $ReportPath,

    [Parameter(mandatory=$true, ParametersetName = 'AvailabilitySet')]
    [Parameter(mandatory=$true, ParametersetName = 'VirtualMachine')]
    [string]
    $Filename
)

# CSV FileName
$CSVFileName = $Filename + '_VmResizeReport_' + $(Get-Date -f yyyy-MM-dd) + '.csv'
Write-host "Writing output to:" $ReportPath\$CSVFileName

# Creating DataTable Structure
$DataTable = New-Object System.Data.DataTable
$DataTable.Columns.Add("Hostname","string") | Out-Null
$DataTable.Columns.Add("ResourceGroup","string") | Out-Null
$DataTable.Columns.Add("OldVMsize","string") | Out-Null
$DataTable.Columns.Add("NewVMSize","string") | Out-Null
$DataTable.Columns.Add("ErrorMessage","string") | Out-Null

#region resize virtual machine not in an availability set
if(!$availabilitySetName -and $VmList)
{
    foreach($virtualMachine in $vmList)
    {
        $vmSize = Get-AzVMSize -ResourceGroupName $resourceGroup -VMName $virtualMachine
        $vm = Get-AzVM -ResourceGroupName $resourceGroup -VMName $virtualMachine
        $oldVmSize = $vm.HardwareProfile.VmSize

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

                $updateVmjob = Update-AzVM -VM $vm -ResourceGroupName $resourceGroup -AsJob

                do{
                    $status = Get-Job -id $updateVmjob.Id
                    Write-Host "Resizing" $vm.Name
                    Start-Sleep 5
                } while ($status.State -eq "Running")

                Write-Host '----------------------------------------------------------------------------------------'
                Write-Host 'Resize of Virtual Machine' $vm.Name "has" $status.State
                Write-Host '----------------------------------------------------------------------------------------'

                # Check VM Size after updating
                $vmSize = Get-AzVMSize -ResourceGroupName $resourceGroup -VMName $virtualMachine

                foreach ($job in $updateVmJob)
                {
                    if ($job.State -eq 'Failed')
                    {
                        $message = $job.Error
                        Write-host "Failed Resizing VM" $vmName "please review report" "$ReportPath\$CSVFileName"
                        Add-ErrorRowToCSV
                    }
                    # Append data to CSV File
                    elseif($job.State -eq "Completed")
                    {
                        Add-RowToCSV
                    }
                }

            }
            else
            {
                Write-Host '----------------------------------------------------------------------------------------'
                Write-Host 'Virtual Machine' $virtualMachine "is already sized at" $NewVmSize
                Write-Host '----------------------------------------------------------------------------------------'
            }
        }
        else
        {
            Write-Host '----------------------------------------------------------------------------------------'
            Write-Host 'Sku NOT found on hardware cluster' $($vm.AvailabilitySetReference.id)
            Write-Host '----------------------------------------------------------------------------------------'
            Resize-VmSkuNotFound
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
    # Shutting down VMs in AS
    $stopJobList = @()
    foreach ($vmId in $vmIds)
    {
        $string = $vmId.Id.Split("/")
        $vmName = $string[8]
        $stopJobList += Stop-AzVm -ResourceGroupName $resourceGroup -Name $vmName -Force -AsJob | Add-Member -MemberType NoteProperty -Name VMName -Value $vmName -PassThru
    }
    do{
        Write-Host "Stopping all virtual machines in" $($availabilitySetName) "in" $ResourceGroup
        Start-Sleep 5
    } while ($stopJobList.State -contains "Running")

    foreach ($vmId in $vmIDs)
    {
        $string = $vmID.Id.Split("/")
        $vmName = $string[8]
        $vm = Get-AzVM -ResourceGroupName $resourceGroup -Name $vmName
        $oldVmSize = $vm.HardwareProfile.VmSize
        If($PathtoCsv)
        {
            $NewVmSize = ($ResizeExtract | Where-Object {$_.hostname -match $vmname}).ToBeVmSize
        }
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

            foreach ($job in $updateVmJob)
            {
                if ($job.State -eq 'Failed')
                {
                    $message = $job.Error
                    Write-host "Failed Resizing VM" $vmName "please review report" "$ReportPath\$CSVFileName"
                    Add-ErrorRowToCSV
                }
                 # Append data to CSV File
                elseif($job.State -eq "Completed")
                {
                    Add-RowToCSV
                }
            }
        }
        else
        {
            Write-Host '----------------------------------------------------------------------------------------'
            Write-Host 'Virtual Machine' $vm.name 'is already right sized to' $newVmSize
            Write-Host '----------------------------------------------------------------------------------------'
        }
    }
    $startJobList = @()
    foreach ($vmId in $vmIds)
    {
        $string = $vmId.Id.Split("/")
        $vmName = $string[8]
        $startJobList += Start-AzVM -ResourceGroupName $resourceGroup -Name $vmName -AsJob | Add-Member -MemberType NoteProperty -Name VMName -Value $vmName -PassThru
    }
    do{
        Write-Host "Starting VMs in" $($availabilitySetName)
        Start-Sleep 5
    } while ($startJobList.State -contains "Running")
}
$DataTable | Export-Csv "$ReportPath\$CSVFileName" -NoTypeInformation -Append -Force
Remove-Jobs
}
#endregion

Function Remove-Jobs {
    if($startJobList)
    {
        $startJobList | Remove-Job
    }
    if($stopJobList)
    {
        $stopJobList | Remove-Job
    }
    if($updateVmJob)
    {
        $updateVmJob | Remove-Job
    }
}
Function Add-RowToCSV {
    $NewRow = $DataTable.NewRow()
    $NewRow.Hostname = $($vm.Name)
    $NewRow.ResourceGroup = $($vm.ResourceGroupName)
    $NewRow.OldVMsize = $($oldVmSize)
    $NewRow.NewVmSize = $($NewVmSize)
    $DataTable.Rows.Add($NewRow)
}
Function Add-ErrorRowToCSV {
    $NewRow = $DataTable.NewRow()
    $NewRow.Hostname = $($vm.Name)
    $NewRow.ResourceGroup = $($vm.ResourceGroupName)
    $NewRow.OldVMsize = $($oldVmSize)
    $NewRow.NewVmSize = "Not Resized"
    $NewRow.ErrorMessage = $($message)
    $DataTable.Rows.Add($NewRow)
}

Function Resize-VmSkuNotFound {
    $vm = Get-AzVM -ResourceGroupName $resourceGroup -VMName $virtualMachine
    $oldVmSize = $vm.HardwareProfile.VmSize
    $vm.HardwareProfile.VmSize = $newVmSize

    $stopJobList = @()
    $stopJobList += Stop-AzVm -ResourceGroupName $resourceGroup -Name $vm.name -Force -AsJob | Add-Member -MemberType NoteProperty -Name VMName -Value $vm.name -PassThru

    do{
        Write-Host "Stopping virtual machine" $vm.name "in" $ResourceGroup
        Start-Sleep 5
    } while ($stopJobList.State -contains "Running")


    Write-Host '----------------------------------------------------------------------------------------'
    Write-Host 'Resizing Virtual Machine' $vm.Name "to Sku size" $newVmSize
    Write-Host '----------------------------------------------------------------------------------------'

    $updateVmjob = Update-AzVM -VM $vm -ResourceGroupName $resourceGroup -AsJob

    do{
        $status = Get-Job -id $updateVmjob.Id
        Write-Host "Resizing" $vm.Name
        Start-Sleep 5
    } while ($status.State -eq "Running")

    Write-Host '----------------------------------------------------------------------------------------'
    Write-Host 'Resize of Virtual Machine' $vm.Name "has" $status.State
    Write-Host '----------------------------------------------------------------------------------------'

    # Check VM Size after updating
    $vmSize = Get-AzVMSize -ResourceGroupName $resourceGroup -VMName $vm.name

    foreach ($job in $updateVmJob)
    {
        if ($job.State -eq 'Failed')
        {
            $message = $job.Error
            Write-host "Failed Resizing VM" $($vm.name) "please review report" "$ReportPath\$CSVFileName"
            Add-ErrorRowToCSV
        }
        # Append data to CSV File
        elseif($job.State -eq "Completed")
        {
            $startJobList = @()
            $startJobList += Start-AzVM -ResourceGroupName $resourceGroup -Name $vm.name -AsJob | Add-Member -MemberType NoteProperty -Name VMName -Value $vm -PassThru
            do{
                Write-Host "Starting VMs" $($vm.name)
                Start-Sleep 5
            } while ($startJobList.State -contains "Running")
            Add-RowToCSV
        }
    }
}

if($PathtoCsv)
{
    # Import extract file data
    $ResizeExtract = Import-Csv -Path $PathtoCsv

    # Find availability sets in csv
    $availabilitySets = $ResizeExtract | Select-Object -Property AvailabilitySet, ResourceGroup -Unique

    #region Resize virtual machines not in an availability set
    foreach($hostname in $ResizeExtract)
    {
        if(!$hostname.AvailabilitySet)
        {
            Resize-Vm -VmList $hostname.hostname -NewVmSize $hostname.ToBeVmSize -ResourceGroup $hostname.ResourceGroup -ReportPath $ReportPath -Filename $Filename
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
                Resize-Vm -AvailabilitySetName $as.AvailabilitySet -ResourceGroup $as.ResourceGroup -ReportPath $ReportPath -Filename $Filename
            }
        }
    }
    #endregion
}