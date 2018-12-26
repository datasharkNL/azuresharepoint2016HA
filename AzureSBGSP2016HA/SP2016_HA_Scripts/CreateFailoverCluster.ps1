# DomainName                   - Active Directory Domain e.g.: bhc
# AdminCreds                   - Active Directory Domain Admin PSCredentials object
# SQLServiceCreds              - SQL service user PSCredentials object
# ClusterName                  - FailOver Cluster name
# SharePath                    - FailOver Cluster resource path
# AvGroupName                  - Availability Group name
# AvListenerName               - Availability Group Listener name
# AvListenerPort               - Availability Group Listener port
# LBName                       - Load Balancer name
# LBAddress                    - Load Balancer IP Address
# PrimaryReplica               - Failover Cluster Primary Replica name
# SecondaryReplica             - Failover Cluster Secondary Replica name
# AOEndpointName               - SQL Always On endpoint name
# DNSServerName                - DNS Server name
# DatabaseNames                - Database Names
# DatabaseEnginePort           - Database Port
# RetryCount                   - Defines how many retries should be performed while waiting for the domain to be provisioned
# RetryIntervalSec             - Defines the seconds between each retry to check if the domain has been provisioned
configuration CreateFailoverCluster
{
    param
    (
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$SQLServiceCreds,

        [Parameter(Mandatory)]
        [String]$ClusterName,

        [Parameter(Mandatory)]
        [String]$SharePath,

        [Parameter(Mandatory)]
        [String]$AvGroupName,

        [Parameter(Mandatory)]
        [String]$AvListenerName,

        [Parameter(Mandatory)]
        [UInt32]$AvListenerPort,

        [Parameter(Mandatory)]
        [String]$LBName,

        [Parameter(Mandatory)]
        [String]$LBAddress,

        [Parameter(Mandatory)]
        [String]$PrimaryReplica,

        [Parameter(Mandatory)]
        [String]$SecondaryReplica,

        [Parameter(Mandatory)]
        [String]$AOEndpointName,

        [String]$DNSServerName='dc-pdc',

        [String]$DatabaseNames = 'AutoHa-Sample',

        [UInt32]$DatabaseEnginePort = 1433,        

        [Int]$RetryCount=20,
        [Int]$RetryIntervalSec=30
    )

    Import-DscResource -ModuleName xComputerManagement, xFailOverCluster, xFOCluster, xActiveDirectory, xStorage, xNetworking, xSQLServer, xPendingReboot

    [string]$DomainNetbiosName=(Get-NetBIOSName -DomainName $DomainName)
    [System.Management.Automation.PSCredential]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainNetbiosName}\$($Admincreds.UserName)", $Admincreds.Password)
    [System.Management.Automation.PSCredential]$DomainFQDNCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($Admincreds.UserName)", $Admincreds.Password)
    [System.Management.Automation.PSCredential]$SQLCreds = New-Object System.Management.Automation.PSCredential ("${DomainNetbiosName}\$($SQLServiceCreds.UserName)", $SQLServiceCreds.Password)
    [string]$LBFQName="${LBName}.${DomainName}"

    Enable-CredSSPNTLM -DomainName $DomainName
    
    WaitForSqlSetup

    Node localhost
    {
        LocalConfigurationManager
        {            
            ActionAfterReboot = 'ContinueConfiguration'            
            ConfigurationMode = 'ApplyOnly'            
            RebootNodeIfNeeded = $true            
        }

        WindowsFeature DNS 
        { 
            Ensure = "Present" 
            Name = "DNS"
            IncludeAllSubFeature = $true
        }        

        WindowsFeature FC
        {
            Name = "Failover-Clustering"
            Ensure = "Present"
            IncludeAllSubFeature = $true
        }

		WindowsFeature FailoverClusterTools 
        { 
            Ensure = "Present" 
            Name = "RSAT-Clustering-Mgmt"
            IncludeAllSubFeature = $true
			DependsOn = "[WindowsFeature]FC"
        } 

        WindowsFeature FCPS
        {
            Name = "RSAT-Clustering-PowerShell"
            IncludeAllSubFeature = $true
            Ensure = "Present"
        }

        WindowsFeature ADPS
        {
            Name = "RSAT-AD-PowerShell"
            IncludeAllSubFeature = $true
            Ensure = "Present"
        }

        WindowsFeature AddRemoteServerAdministrationToolsClusteringCmdInterfaceFeature
        {
            Ensure    = 'Present'
            Name      = 'RSAT-Clustering-CmdInterface'
            IncludeAllSubFeature = $true
            DependsOn = '[WindowsFeature]FCPS'
        }
        
        xWaitForADDomain DscForestWait 
        { 
            DomainName = $DomainName 
            DomainUserCredential= $DomainCreds
            RetryCount = $RetryCount 
            RetryIntervalSec = $RetryIntervalSec 
	        DependsOn = "[WindowsFeature]ADPS"
        }
        
        xComputer DomainJoin
        {
            Name = $env:COMPUTERNAME
            DomainName = $DomainName
            Credential = $DomainCreds
	        DependsOn = "[xWaitForADDomain]DscForestWait"
        }

        xFirewall DatabaseEngineFirewallRule
        {
            Direction = "Inbound"
            Name = "SQL-Server-Database-Engine-TCP-In"
            DisplayName = "SQL Server Database Engine (TCP-In)"
            Description = "Inbound rule for SQL Server to allow TCP traffic for the Database Engine."
            Group = "SQL Server"
            Enabled = $true
            Action = 'Allow'
            Protocol = "TCP"
            LocalPort = $DatabaseEnginePort -as [String]
            Ensure = "Present"
        }

        xFirewall DatabaseMirroringFirewallRule
        {
            Direction = "Inbound"
            Name = "SQL-Server-Database-Mirroring-TCP-In"
            DisplayName = "SQL Server Database Mirroring (TCP-In)"
            Description = "Inbound rule for SQL Server to allow TCP traffic for the Database Mirroring."
            Group = "SQL Server"
            Enabled = $true
            Action = 'Allow'
            Protocol = "TCP"
            LocalPort = "5022"
            Ensure = "Present"
        }

        xFirewall ListenerFirewallRule
        {
            Direction = "Inbound"
            Name = "SQL-Server-Availability-Group-Listener-TCP-In"
            DisplayName = "SQL Server Availability Group Listener (TCP-In)"
            Description = "Inbound rule for SQL Server to allow TCP traffic for the Availability Group listener."
            Group = "SQL Server"
            Enabled = $true
            Action = 'Allow'
            Protocol = "TCP"
            LocalPort = "59999"
            Ensure = "Present"
        }

        xSQLServerLogin AddDomainAdminAccountToSysadminServerRole
        {
            Ensure               = 'Present'
            Name                 = $DomainCreds.UserName
            LoginType            = 'WindowsUser'
            SQLServer            = $env:ComputerName
            SQLInstanceName      = "MSSQLSERVER"
            PsDscRunAsCredential = $Admincreds
        }

        xADUser CreateSqlServerServiceAccount
        {
            DomainAdministratorCredential = $DomainCreds
            DomainName = $DomainName
            UserName = $SQLServicecreds.UserName
            Password = $SQLServicecreds
            Ensure = "Present"
            DependsOn = "[xSQLServerLogin]AddDomainAdminAccountToSysadminServerRole"
        }

        xSQLServerLogin AddSqlServerServiceAccountToSysadminServerRole
        {
            Ensure = 'Present'
            Name = $SQLCreds.UserName
            LoginType = "WindowsUser"
            SQLServer            = $env:ComputerName
            SQLInstanceName      = "MSSQLSERVER"           
            PsDscRunAsCredential = $Admincreds
            DependsOn = "[xADUser]CreateSqlServerServiceAccount"
        }
        
        $Nodes = $PrimaryReplica, $SecondaryReplica

        xFOCluster FailoverCluster
        {
            Ensure = 'Present'
            ClusterName = $ClusterName
            Nodes = $Nodes
            StaticAddress = "10.0.3.7"
            PsDscRunAsCredential = $DomainCreds
        }

        xWaitForCluster WaitForCluster
        {
            Name             = $ClusterName
            RetryIntervalSec = 10
            RetryCount       = 30
            DependsOn        = "[xFOCluster]FailoverCluster"
        }
        
        xClusterQuorum ClusterConfigureQuorum
        {
            IsSingleInstance = 'Yes'
            Type = 'NodeAndFileShareMajority'
            Resource = $SharePath
            PsDscRunAsCredential = $Admincreds
            DependsOn = "[xWaitForCluster]WaitForCluster"
        }

        xSQLServerAlwaysOnService ConfigureSqlServerWithAlwaysOn
        {
            Ensure               = 'Present'
            SQLServer            = $env:ComputerName
            SQLInstanceName      = 'MSSQLSERVER'
            RestartTimeout       = 120
            PsDscRunAsCredential = $Admincreds
            DependsOn = "[xWaitForCluster]WaitForCluster"
        }

        Script AddLoadBalancer
        {
            GetScript = {return @{}}
            
            TestScript = { return $false; } # Is always run

            SetScript = 
            {
                Write-Verbose -Message 'Adding DNS Arecord - xSQLAddListenerIPToDNS AddLoadBalancer.'
                Add-DnsServerResourceRecordA -Name $using:LBName -ZoneName $using:DomainName -IPv4Address $using:LBAddress -ComputerName $using:DNSServerName -ErrorAction SilentlyContinue
            }
            PsDscRunAsCredential = $Admincreds
        }
        
       xSQLServerEndpoint SqlAlwaysOnEndpoint
       {
           SQLServer            = $env:ComputerName
           SQLInstanceName      = 'MSSQLSERVER'
           EndpointName         = $AOEndpointName
           Port                 = 5022
           PsDscRunAsCredential = $Admincreds
           DependsOn = "[xSQLServerAlwaysOnService]ConfigureSqlServerWithAlwaysOn"
       }
       
        # Adding the required service account to allow the cluster to log into SQL
        xSQLServerLogin AddNTServiceClusSvc
        {
            Ensure               = 'Present'
            Name                 = 'NT SERVICE\ClusSvc'
            LoginType            = 'WindowsUser'
            SQLServer            = $env:ComputerName
            SQLInstanceName      = 'MSSQLSERVER'
            PsDscRunAsCredential = $Admincreds
        }

        # Add the required permissions to the cluster service login
        xSQLServerPermission AddNTServiceClusSvcPermissions
        {
            DependsOn            = '[xSQLServerLogin]AddNTServiceClusSvc'
            Ensure               = 'Present'
            NodeName             = $env:ComputerName
            InstanceName         = 'MSSQLSERVER'
            Principal            = 'NT SERVICE\ClusSvc'
            Permission           = 'AlterAnyAvailabilityGroup', 'ViewServerState'
            PsDscRunAsCredential = $Admincreds
        }

        xSQLServerPermission AddDomainUserPermissions
        {
            Ensure               = 'Present'
            NodeName             = $env:ComputerName
            InstanceName         = 'MSSQLSERVER'
            Principal            = $DomainCreds.UserName
            Permission           = 'AlterAnyAvailabilityGroup', 'ViewServerState'
            PsDscRunAsCredential = $Admincreds
        }

        xSQLServerAlwaysOnAvailabilityGroup SqlAG
        {
            Ensure               = 'Present'
            Name                 = $AvGroupName
            SQLInstanceName      = 'MSSQLSERVER'
            SQLServer            = $env:ComputerName
            DependsOn            = '[xSQLServerPermission]AddNTServiceClusSvcPermissions'
            PsDscRunAsCredential = $Admincreds
        }

        xSQLServerAlwaysOnAvailabilityGroupDatabaseMembership SQLAGDatabases
        {
            AvailabilityGroupName   = $AvGroupName
            BackupPath              = '\\SQL2\AgInitialize'
            DatabaseName            = $DatabaseNames
            SQLServer               = $env:ComputerName
            SQLInstanceName         = "MSSQLSERVER"
            Ensure                  = 'Present'
            ProcessOnlyOnActiveNode = $true
            PsDscRunAsCredential    = $Admincreds
        }
    
        xSQLServerAvailabilityGroupListener SqlAGListener
        {
            Name = $AvListenerName
            Ensure               = 'Present'
            NodeName             = $env:ComputerName
            InstanceName         = 'MSSQLSERVER'
            AvailabilityGroup    = $AvGroupName
            IpAddress            = "$LBAddress/255.255.255.0"
            Port                 = $AvListenerPort
            PsDscRunAsCredential = $Admincreds
        }

        Script SetClusterProbePort
        {
            GetScript = {return @{}}
            
            TestScript = { return $false; } # Is always run

            SetScript = 
            {
                Write-Verbose -Message 'Adding Probe Port.'

                Write-Verbose -Message 'Get IP Address resource name'
                $IPResourceName = ''
                $resources = Get-ClusterResource
                Foreach ($res IN $resources)
                {
                    If($res.ResourceType.Name -eq "IP Address" -and $res.OwnerGroup -eq $using:AvGroupName)
                    {
                        $IPResourceName = $res.Name
                    }
                }

                Write-Verbose -Message 'Get network name'
                $ClusterNetworkName = (Get-ClusterNetwork).Name
                
                $ILBIP = $using:LBAddress # the IP Address of the Internal Load Balancer
                [int]$ProbePort = 59999
                
                Write-Verbose -Message 'Set cluster parameters'
                Get-ClusterResource $IPResourceName | Set-ClusterParameter -Multiple @{"Address"="$ILBIP";"ProbePort"=$ProbePort;"SubnetMask"="255.255.255.0";"Network"="$ClusterNetworkName";"EnableDhcp"=0}

                Write-Verbose -Message 'Cluster parameters were set'
            }
            PsDscRunAsCredential = $Admincreds
            DependsOn = "[xSQLServerAvailabilityGroupListener]SqlAGListener"
        }
        
        xPendingReboot Reboot1
        { 
            Name = "RebootServer"
            DependsOn = "[xSQLServerAvailabilityGroupListener]SqlAGListener"
        }        

    }

}
function Update-DNS
{
    param(
        [string]$LBName,
        [string]$LBAddress,
        [string]$DomainName

        )
               
        $ARecord=Get-DnsServerResourceRecord -Name $LBName -ZoneName $DomainName -ErrorAction SilentlyContinue -RRType A
        if (-not $Arecord)
        {
            Add-DnsServerResourceRecordA -Name $LBName -ZoneName $DomainName -IPv4Address $LBAddress
        }
}
function WaitForSqlSetup
{
    # Wait for SQL Server Setup to finish before proceeding.
    while ($true)
    {
        try
        {
            Get-ScheduledTaskInfo "\ConfigureSqlImageTasks\RunConfigureImage" -ErrorAction Stop
            Start-Sleep -Seconds 5
        }
        catch
        {
            break
        }
    }
}
function Get-NetBIOSName
{ 
    [OutputType([string])]
    param(
        [string]$DomainName
    )

    if ($DomainName.Contains('.')) {
        $length=$DomainName.IndexOf('.')
        if ( $length -ge 16) {
            $length=15
        }
        return $DomainName.Substring(0,$length)
    }
    else {
        if ($DomainName.Length -gt 15) {
            return $DomainName.Substring(0,15)
        }
        else {
            return $DomainName
        }
    }
}
function Enable-CredSSPNTLM
{ 
    param(
        [Parameter(Mandatory=$true)]
        [string]$DomainName
    )
    
    # This is needed for the case where NTLM authentication is used

    Write-Verbose 'STARTED:Setting up CredSSP for NTLM'
   
    Enable-WSManCredSSP -Role client -DelegateComputer localhost, *.$DomainName -Force -ErrorAction SilentlyContinue
    Enable-WSManCredSSP -Role server -Force -ErrorAction SilentlyContinue

    if(-not (Test-Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -ErrorAction SilentlyContinue))
    {
        New-Item -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows -Name '\CredentialsDelegation' -ErrorAction SilentlyContinue
    }

    if( -not (Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -Name 'AllowFreshCredentialsWhenNTLMOnly' -ErrorAction SilentlyContinue))
    {
        New-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -Name 'AllowFreshCredentialsWhenNTLMOnly' -value '1' -PropertyType dword -ErrorAction SilentlyContinue
    }

    if (-not (Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -Name 'ConcatenateDefaults_AllowFreshNTLMOnly' -ErrorAction SilentlyContinue))
    {
        New-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -Name 'ConcatenateDefaults_AllowFreshNTLMOnly' -value '1' -PropertyType dword -ErrorAction SilentlyContinue
    }

    if(-not (Test-Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly -ErrorAction SilentlyContinue))
    {
        New-Item -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -Name 'AllowFreshCredentialsWhenNTLMOnly' -ErrorAction SilentlyContinue
    }

    if (-not (Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly -Name '1' -ErrorAction SilentlyContinue))
    {
        New-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly -Name '1' -value "wsman/$env:COMPUTERNAME" -PropertyType string -ErrorAction SilentlyContinue
    }

    if (-not (Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly -Name '2' -ErrorAction SilentlyContinue))
    {
        New-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly -Name '2' -value "wsman/localhost" -PropertyType string -ErrorAction SilentlyContinue
    }

    if (-not (Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly -Name '3' -ErrorAction SilentlyContinue))
    {
        New-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly -Name '3' -value "wsman/*.$DomainName" -PropertyType string -ErrorAction SilentlyContinue
    }

    Write-Verbose "DONE:Setting up CredSSP for NTLM"
}