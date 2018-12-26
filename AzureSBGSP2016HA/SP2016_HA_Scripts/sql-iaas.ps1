configuration SQLIaasExtension
{
    param
    (
        [Parameter(Mandatory)]
        [String]$ResourceGroupName,

        [Parameter(Mandatory)]
        [String]$Location
    )

    Node localhost
    {    
        LocalConfigurationManager            
        {            
            ActionAfterReboot = "ContinueConfiguration"
            ConfigurationMode = "ApplyOnly"
            RebootNodeIfNeeded = $true       
        }

        Script InstallSQLIaasExtension 
        {
            GetScript = { return @{} }

            TestScript = {
                return $false
            }

            SetScript = {
                Write-Verbose -Message 'Begin SQLIaasExtension installation.'

                $PatchingConfig = New-AzureVMSqlServerAutoPatchingConfig -Enable `
                -DayOfWeek "Sunday" `
                -MaintenanceWindowStartingHour 12 -MaintenanceWindowDuration 60 `
                -PatchCategory "WindowsMandatoryUpdates"

                $BackupConfig = New-AzureRmVMSqlServerAutoBackupConfig  `
                -RetentionPeriodInDays 30 `
                -ResourceGroupName $using:Resourcegroupname
            
                Set-AzureRmVMSqlServerExtension -AutoBackupSettings $BackupConfig `
                -AutoPatchingSettings $PatchingConfig `
                -ResourceGroupName $using:Resourcegroupname `
                -VMName localhost -Name "SQLIaasExtension" -Version "1.2" `
                -Location $using:Location

                Write-Verbose -Message 'SQLIaasExtension was installed.'
            }
        }
    }
}