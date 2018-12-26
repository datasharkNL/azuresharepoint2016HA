# DomainName           - Active Directory Domain e.g.: bhc.sa
# PrimaryDcIpAddress   - IP address of primary domain controller
# AdminCreds           - Active Directory Domain Admin PSCredentials object
Configuration JoinDomain {
    param
    #v1.4
    (
        [Parameter(Mandatory)]
        [string]$DomainName,

        [Parameter(Mandatory)]
        [string]$PrimaryDcIpAddress,       
      
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$AdminCreds
    )

    Import-DscResource -ModuleName xComputerManagement, xNetworking
       
    [System.Management.Automation.PSCredential ]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($AdminCreds.UserName)", $AdminCreds.Password)

    $Interface = Get-NetAdapter|Where-Object Name -Like "Ethernet*"|Select-Object -First 1
    $InterfaceAlias = $($Interface.Name)

    Node localhost
    {
        [ScriptBlock]$SetScript =
        {
            Set-DnsClientServerAddress -InterfaceAlias ("$InterfaceAlias") -ServerAddresses ("$PrimaryDcIpAddress")
        }

        Script SetDnsServerAddressToFindPDC
        {
            GetScript = {return @{}}
            TestScript = {return $false} # Always run the SetScript for this.
            SetScript = $SetScript.ToString().Replace('$PrimaryDcIpAddress', $PrimaryDcIpAddress).Replace('$InterfaceAlias', $InterfaceAlias)
        }

        xComputer JoinDomain
        {
            DomainName = $DomainName
            Credential = $DomainCreds
            Name = "localhost"
        }

        # Now make sure this computer uses itself as a DNS source
        xDnsServerAddress DnsServerAddress
        {
            Address        = @('127.0.0.1', $PrimaryDcIpAddress)
            InterfaceAlias = $InterfaceAlias
            AddressFamily  = 'IPv4'
        }        
   }
}