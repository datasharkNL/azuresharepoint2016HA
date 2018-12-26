configuration CreateJoinFarm
{
    param
    (
        [Parameter(Mandatory)]
        [String]$domainName,
		
        [Parameter(Mandatory)]
        [String]$DomainFQDNName,
		
        [Parameter(Mandatory)]
        [String]$SqlAlwaysOnEndpointName,
		
        [Parameter(Mandatory)]
        [String]$ServerRole,

        [Parameter(Mandatory)] 
        [String]$driveletter,
		
        [Parameter(Mandatory)] 
        [String]$CentralAdmin,
		
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Passphrase,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$FarmAccount,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$SPSetupAccount,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$ServicePoolManagedAccount,
		
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$WebPoolManagedAccount,
		
        [String] $SuperUserAlias = "sp_superuser",
        [String] $SuperReaderAlias = "sp_superreader",
        [string]$webAppPoolName = "SharePoint Sites",
        [string]$serviceAppPoolName = "Service App Pool",
		
        [Int]$RetryCount = 20,
        [Int]$RetryIntervalSec = 30
    )
	
    [System.Management.Automation.PSCredential]$FarmAccountCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($FarmAccount.UserName)", $FarmAccount.Password)
    [System.Management.Automation.PSCredential]$SPSetupAccountCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($SPSetupAccount.UserName)", $SPSetupAccount.Password) 
    [System.Management.Automation.PSCredential]$ServicePoolManagedAccountCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($ServicePoolManagedAccount.UserName)", $ServicePoolManagedAccount.Password) 
    [System.Management.Automation.PSCredential]$WebPoolManagedAccountCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($WebPoolManagedAccount.UserName)", $WebPoolManagedAccount.Password) 

    Import-DscResource -ModuleName PSDesiredStateConfiguration, xStorage, xComputerManagement, xActiveDirectory, SharePointDsc, xWebAdministration, xCredSSP

    $RebootVirtualMachine = $false
    $PSDscAllowDomainUser = $true
    if ($DomainName)
    {
        $RebootVirtualMachine = $true
    }
    $runCentralAdmin = $false
    if ($CentralAdmin.ToLower() -eq "true")
    {
        $runCentralAdmin = $true
    }
	
    node localhost
    {
        xWaitforDisk Disk2
        {
            DiskNumber = 2
            RetryIntervalSec = $RetryIntervalSec
            RetryCount = $RetryCount
        }

        xDisk ADDataDisk2
        {
            DiskNumber = 2
            DriveLetter = $driveletter
            FSLabel = 'Data'
            DependsOn = '[xWaitforDisk]Disk2'
        }
		
        WindowsFeature ADPowerShell
        {
            Ensure = "Present"
            Name = "RSAT-AD-PowerShell"
            DependsOn = '[xDisk]ADDataDisk2'
        }

        xWaitForADDomain DscForestWait 
        { 
            DomainName = $DomainFQDNName
            DomainUserCredential= $SPSetupAccountCreds
            RetryCount = $RetryCount 
            RetryIntervalSec = $RetryIntervalSec 
	        DependsOn = "[WindowsFeature]ADPowerShell"
        }

        xComputer DomainJoin
        {
            Name = $env:COMPUTERNAME
            DomainName = $DomainFQDNName
            Credential = $SPSetupAccountCreds
	        DependsOn = "[xWaitForADDomain]DscForestWait"
        }

        WindowsFeature DNSPowerShell
        {
            Ensure = "Present"
            Name = "RSAT-DNS-Server"
            DependsOn = '[xDisk]ADDataDisk2'
        }

        xWebAppPool RemoveDotNet2Pool         { Name = ".NET v2.0";            Ensure = "Absent"; }
        xWebAppPool RemoveDotNet2ClassicPool  { Name = ".NET v2.0 Classic";    Ensure = "Absent"; }
        xWebAppPool RemoveDotNet45Pool        { Name = ".NET v4.5";            Ensure = "Absent"; }
        xWebAppPool RemoveDotNet45ClassicPool { Name = ".NET v4.5 Classic";    Ensure = "Absent"; }
        xWebAppPool RemoveClassicDotNetPool   { Name = "Classic .NET AppPool"; Ensure = "Absent"; }
        xWebAppPool RemoveDefaultAppPool      { Name = "DefaultAppPool";       Ensure = "Absent"; }
        xWebSite    RemoveDefaultWebSite      
        { 
            Name = "Default Web Site";     
            Ensure = "Absent"; 
            PhysicalPath = "C:\inetpub\wwwroot"; 
        }

        xADUser CreateFarmAccount
        {
            DomainName = $domainName
            UserName = $FarmAccount.UserName
            DisplayName = "SharePoint Farm Account"
            PasswordNeverExpires = $true            
            Ensure = 'Present'
            Password = $FarmAccountCreds
            DomainAdministratorCredential = $SPSetupAccountCreds
            DependsOn = "[xComputer]DomainJoin"
        }
		
        xADUser ServicePoolManagedAccount
        {
            DomainName = $domainName
            UserName = $ServicePoolManagedAccount.UserName
            DisplayName = "Service Pool Account"
            PasswordNeverExpires = $true            
            Ensure = "Present"
            Password = $ServicePoolManagedAccountCreds
            DomainAdministratorCredential = $SPSetupAccountCreds
            DependsOn = "[xComputer]DomainJoin"
        }		

        xADUser WebPoolManagedAccount
        {
            DomainName = $domainName
            UserName = $WebPoolManagedAccount.UserName
            DisplayName = "Web App Pool Account"
            PasswordNeverExpires = $true            
            Ensure = "Present"
            Password = $WebPoolManagedAccountCreds
            DomainAdministratorCredential = $SPSetupAccountCreds
            DependsOn = "[xADUser]ServicePoolManagedAccount"
        }		

        SPFarm CreateSPFarm
        {
            Ensure = "Present"
            DatabaseServer = $SqlAlwaysOnEndpointName
            FarmConfigDatabaseName = "SP_Config_2016"
            Passphrase = $Passphrase
            FarmAccount = $FarmAccountCreds
            PsDscRunAsCredential = $SPSetupAccount
            AdminContentDatabaseName = "SP_AdminContent"
            CentralAdministrationPort = "2016"
            RunCentralAdmin = $runCentralAdmin
            ServerRole = $ServerRole
            DependsOn = @("[xADUser]CreateFarmAccount", "[xADUser]ServicePoolManagedAccount", "[xADUser]WebPoolManagedAccount")
        }

        xCredSSP CredSSPServer
        { 
            Ensure = "Present"
            Role = "Server"
        } 
       
        xCredSSP CredSSPClient
        { 
            Ensure = "Present"
            Role = "Client"
            DelegateComputers = "*.$DomainFQDNName"
        }

        xADUser SPSuperUser
        {
            DomainName = $domainName
            UserName = $SuperUserAlias
            DisplayName = "SuperUser Cache Account"
            PasswordNeverExpires = $true            
            Ensure = 'Present'
            Password = $Passphrase
            DomainAdministratorCredential = $SPSetupAccountCreds
            DependsOn = "[xComputer]DomainJoin"
        }

        xADUser SPSuperReader
        {
            DomainName = $domainName
            UserName = $SuperReaderAlias
            DisplayName = "SuperReader Cache Account"
            PasswordNeverExpires = $true            
            Ensure = 'Present'
            Password = $Passphrase
            DomainAdministratorCredential = $SPSetupAccountCreds
            DependsOn = "[xComputer]DomainJoin"
        }		

        SPManagedAccount ServicePoolManagedAccount
        {
            AccountName = $ServicePoolManagedAccountCreds.UserName
            Account = $ServicePoolManagedAccountCreds
            PsDscRunAsCredential = $SPSetupAccount
            Ensure = 'Present'
            DependsOn = @("[SPFarm]CreateSPFarm", "[xADUser]ServicePoolManagedAccount")
        }


        SPManagedAccount WebPoolManagedAccount
        {
            AccountName = $WebPoolManagedAccountCreds.UserName
            Account = $WebPoolManagedAccountCreds
            Ensure = 'Present'
            PsDscRunAsCredential = $SPSetupAccount
            DependsOn = @("[SPFarm]CreateSPFarm", "[xADUser]WebPoolManagedAccount")
        }

        SPDiagnosticLoggingSettings ApplyDiagnosticLogSettings
        {
            PsDscRunAsCredential = $SPSetupAccount
            LogPath = "F:\ULS"
            LogSpaceInGB = 5
            AppAnalyticsAutomaticUploadEnabled = $false
            CustomerExperienceImprovementProgramEnabled = $true
            DaysToKeepLogs = 7
            DownloadErrorReportingUpdatesEnabled = $false
            ErrorReportingAutomaticUploadEnabled = $false
            ErrorReportingEnabled = $false
            EventLogFloodProtectionEnabled = $true
            EventLogFloodProtectionNotifyInterval = 5
            EventLogFloodProtectionQuietPeriod = 2
            EventLogFloodProtectionThreshold = 5
            EventLogFloodProtectionTriggerPeriod = 2
            LogCutInterval = 15
            LogMaxDiskSpaceUsageEnabled = $true
            ScriptErrorReportingDelay = 30
            ScriptErrorReportingEnabled = $true
            ScriptErrorReportingRequireAuth = $true
            DependsOn = @("[SPFarm]CreateSPFarm", "[SPManagedAccount]WebPoolManagedAccount")
        }
 
        SPUsageApplication UsageApplication
        {
            Name = "Usage Service Application"
            DatabaseName = "SP2016_Usage"
            UsageLogCutTime = 5
            UsageLogLocation = "F:\UsageLogs"
            UsageLogMaxFileSizeKB = 1024
            PsDscRunAsCredential = $SPSetupAccount
            DependsOn = @("[SPFarm]CreateSPFarm", "[SPManagedAccount]WebPoolManagedAccount")
        }

        SPStateServiceApp StateServiceApp
        {
            Name = "State Service Application"
            DatabaseName = "SP2016_State"
            PsDscRunAsCredential = $SPSetupAccount
            DependsOn = @("[SPFarm]CreateSPFarm", "[SPManagedAccount]WebPoolManagedAccount")
        }
 
        if ($ServerRole -eq "DistributedCache" -or $ServerRole -eq "SingleServerFarm" -or $ServerRole -eq "Custom" )
        {
            SPDistributedCacheService EnableDistributedCache
            {
                Name = "AppFabricCachingService"
                Ensure = "Present"
                ServerProvisionOrder = @("dch1", "dch2")
                CacheSizeInMB = 1024
                ServiceAccount = $ServicePoolManagedAccountCreds.UserName
                PsDscRunAsCredential = $SPSetupAccount
                CreateFirewallRules = $true
                DependsOn = @("[SPFarm]CreateSPFarm", "[SPManagedAccount]ServicePoolManagedAccount")
            }
        }     
        #**********************************************************
        # Web applications
        #
        # This section creates the web applications in the 
        # SharePoint farm, as well as managed paths and other web
        # application settings
        #**********************************************************

        SPServiceAppPool MainServiceAppPool
        {
            Name = $serviceAppPoolName
            ServiceAccount = $ServicePoolManagedAccountCreds.UserName
            PsDscRunAsCredential = $SPSetupAccount
            DependsOn = @("[SPFarm]CreateSPFarm", "[SPManagedAccount]WebPoolManagedAccount")
        }
        if ($ServerRole -eq "WebFrontEnd")
        {		
            SPWebApplication SharePointSites
            {
                Name = "SharePoint Sites"
                ApplicationPool = $webAppPoolName
                ApplicationPoolAccount = $WebPoolManagedAccountCreds.UserName
                AllowAnonymous = $false
                AuthenticationMethod = "NTLM"
                DatabaseName = "SP2016_Sites_Content"
                Url = "http://Portal.$DomainFQDNName"
                Port = 80
                PsDscRunAsCredential = $SPSetupAccount
                DependsOn = @("[SPFarm]CreateSPFarm", "[SPManagedAccount]WebPoolManagedAccount")
            }
        
            SPWebApplication OneDriveSites
            {
                Name = "OneDrive"
                ApplicationPool = $webAppPoolName
                ApplicationPoolAccount = $WebPoolManagedAccountCreds.UserName
                AllowAnonymous = $false
                AuthenticationMethod = "NTLM"
                DatabaseName = "SP2016_Sites_OneDrive"
                HostHeader = "OneDrive.$DomainFQDNName"
                Url = "http://OneDrive.$DomainFQDNName"
                Port = 80
                PsDscRunAsCredential = $SPSetupAccount
                DependsOn = @("[SPFarm]CreateSPFarm", "[SPManagedAccount]WebPoolManagedAccount")
            }

            SPCacheAccounts WebAppCacheAccounts
            {
                WebAppUrl = "http://Portal.$DomainFQDNName"
                SuperUserAlias = "${DomainName}\$SuperUserAlias"
                SuperReaderAlias = "${DomainName}\$SuperReaderAlias"
                PsDscRunAsCredential = $SPSetupAccount
                DependsOn = "[SPWebApplication]SharePointSites"
            }

            SPCacheAccounts OneDriveCacheAccounts
            {
                WebAppUrl = "http://OneDrive.$DomainFQDNName"
                SuperUserAlias = "${DomainName}\$SuperUserAlias"
                SuperReaderAlias = "${DomainName}\$SuperReaderAlias"
                PsDscRunAsCredential = $SPSetupAccount
                DependsOn = "[SPWebApplication]OneDriveSites"
            }

            SPSite TeamSite
            {
                Url = "http://Portal.$DomainFQDNName"
                OwnerAlias = $SPSetupAccountCreds.UserName
                Name = "Root Demo Site"
                Template = "STS#0"
                PsDscRunAsCredential = $SPSetupAccount
                DependsOn = "[SPWebApplication]SharePointSites"
            }

            SPSite MySiteHost
            {
                Url = "http://OneDrive.$DomainFQDNName"
                OwnerAlias = $SPSetupAccountCreds.UserName
                Name = "OneDrive"
                Template = "SPSMSITEHOST#0"
                PsDscRunAsCredential = $SPSetupAccount
                DependsOn = "[SPWebApplication]OneDriveSites"
            }
        }
        #**********************************************************
        # Service instances
        #
        # This section describes which services should be running
        # and not running on the server
        #**********************************************************

        if ($ServerRole -eq "WebFrontEnd" -or $ServerRole -eq "Application" -or $ServerRole -eq "SingleServerFarm" -or $ServerRole -eq "Custom" )
        {
            SPServiceInstance AppManagementServiceInstance
            {  
                Name = "App Management Service"
                Ensure = "Present"
                PsDscRunAsCredential = $SPSetupAccount
                DependsOn = "[SPServiceAppPool]MainServiceAppPool" 
            }
            SPServiceInstance ManagedMetadataServiceInstance
            {  
                Name = "Managed Metadata Web Service"
                Ensure = "Present"
                PsDscRunAsCredential = $SPSetupAccount
                DependsOn = "[SPServiceAppPool]MainServiceAppPool" 
            }
            SPServiceInstance SubscriptionSettingsServiceInstance
            {  
                Name = "Microsoft SharePoint Foundation Subscription Settings Service"
                Ensure = "Present"
                PsDscRunAsCredential = $SPSetupAccount
                DependsOn = "[SPServiceAppPool]MainServiceAppPool" 
            }
            SPServiceInstance UserProfileServiceInstance
            {  
                Name = "User Profile Service"
                Ensure = "Present"
                PsDscRunAsCredential = $SPSetupAccount
                DependsOn = "[SPServiceAppPool]MainServiceAppPool" 
            }
        }

        if ($ServerRole -eq "Search" -or $ServerRole -eq "SingleServerFarm" -or $ServerRole -eq "Custom" )
        {
            SPServiceInstance SearchServiceInstance
            {  
                Name = "SharePoint Server Search"
                Ensure = "Present"
                PsDscRunAsCredential = $SPSetupAccount
                DependsOn = "[SPServiceAppPool]MainServiceAppPool" 
            }
        }
        #**********************************************************
        # Service applications
        #
        # This section creates service applications and required
        # dependencies
        #**********************************************************

        if ($ServerRole -eq "WebFrontEnd" -or $ServerRole -eq "Application" -or $ServerRole -eq "SingleServerFarm" -or $ServerRole -eq "Custom" )
        {
            SPAppManagementServiceApp AppManagementServiceApp
            {
                Name = "App Management Service Application"
                ApplicationPool = $serviceAppPoolName
                DatabaseName = "SP2016_AppManagement"
                PsDscRunAsCredential = $SPSetupAccount  
                DependsOn = '[SPServiceAppPool]MainServiceAppPool'      
            }

            SPSubscriptionSettingsServiceApp SubscriptionSettingsServiceApp
            {
                Name = "Subscription Settings Service Application"
                ApplicationPool = $serviceAppPoolName
                DatabaseName = "SP2016_SubscriptionSettings"
                PsDscRunAsCredential = $SPSetupAccount
                DependsOn = '[SPServiceAppPool]MainServiceAppPool'      
            }

            SPManagedMetaDataServiceApp ManagedMetadataServiceApp
            {  
                Name = "Managed Metadata Service Application"
                PsDscRunAsCredential = $SPSetupAccount
                ApplicationPool = $serviceAppPoolName
                DatabaseName = "SP2016_MMS"
                DependsOn = @('[SPServiceAppPool]MainServiceAppPool', '[SPServiceInstance]ManagedMetadataServiceInstance')
            }
            if ($ServerRole -eq "WebFrontEnd" )
            {
                SPUserProfileServiceApp UserProfileApp
                {
                    Name = "User Profile Service Application"
                    ProfileDBName = "SP2016_Profile"
                    ProfileDBServer = $SqlAlwaysOnEndpointName
                    SocialDBName = "SP2016_Social"
                    SocialDBServer = $SqlAlwaysOnEndpointName
                    SyncDBName = "SP2016_Sync"
                    SyncDBServer = $SqlAlwaysOnEndpointName
                    MySiteHostLocation = "http://OneDrive.$DomainFQDNName"
                    FarmAccount = $FarmAccountCreds
                    ApplicationPool = $serviceAppPoolName
                    PsDscRunAsCredential = $SPSetupAccount
                    DependsOn = '[SPServiceAppPool]MainServiceAppPool'
                }
            }

            if ($ServerRole -eq "Application" -or $ServerRole -eq "SingleServerFarm" -or $ServerRole -eq "Custom" )
            {
                SPUserProfileServiceApp UserProfileApp
                {
                    Name = "User Profile Service Application"
                    ProfileDBName = "SP2016_Profile"
                    ProfileDBServer = $SqlAlwaysOnEndpointName
                    SocialDBName = "SP2016_Social"
                    SocialDBServer = $SqlAlwaysOnEndpointName
                    SyncDBName = "SP2016_Sync"
                    SyncDBServer = $SqlAlwaysOnEndpointName
                    FarmAccount = $FarmAccountCreds
                    ApplicationPool = $serviceAppPoolName
                    PsDscRunAsCredential = $SPSetupAccount
                    DependsOn = '[SPServiceAppPool]MainServiceAppPool'
                }
            }       
        }
        
        #**********************************************************
        # Local configuration manager settings
        #
        # This section contains settings for the LCM of the host
        # that this configuraiton is applied to
        #**********************************************************
        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
            ActionAfterReboot = 'ContinueConfiguration'
            ConfigurationMode = 'ApplyOnly'
            AllowModuleOverWrite = $true
        }
    }
}
