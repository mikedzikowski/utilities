[CmdletBinding()]
param
(
    [Parameter(mandatory=$true)]
    [string]
    $Filename,
    [Parameter(mandatory=$true)]
    [string]
    $ReportPath,
    [Parameter(mandatory=$true)]
    [string]
    $PathtoCsv
)

Function Add-RowToCSV {
    $NewRow = $DataTable.NewRow()
    $NewRow.Hostname = $($vm.Name)
    $NewRow.ResourceGroup = $($vm.ResourceGroupName)
    $NewRow.NewVmSize = $($NewVmSize)
    $DataTable.Rows.Add($NewRow)
}

$CSVFileName = $Filename + '_VmResizeVerificationReport_' + $(Get-Date -f yyyy-MM-dd) + '.csv'
Write-host "Writing output to:" $ReportPath\$CSVFileName

$DataTable = New-Object System.Data.DataTable
$DataTable.Columns.Add("Hostname","string") | Out-Null
$DataTable.Columns.Add("ResourceGroup","string") | Out-Null
$DataTable.Columns.Add("NewVMSize","string") | Out-Null

$ResizeExtract = Import-Csv -Path $PathtoCsv

foreach($hostname in $ResizeExtract)
{
    $vm = Get-AzVM -ResourceGroupName $hostname.resourceGroup -VMName $hostname.hostname
    $NewVmSize = $vm.HardwareProfile.VmSize
    Add-RowToCSV
}

$DataTable | Export-Csv "$ReportPath\$CSVFileName" -NoTypeInformation -Append -Force

Write-Host "Completed"
