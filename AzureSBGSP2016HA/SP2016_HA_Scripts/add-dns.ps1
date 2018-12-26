Import-Module DNSServer

Add-DnsServerResourceRecordA -Name "Portal" -ZoneName "bhc.sa" -AllowUpdateAny -IPv4Address "10.0.1.100" -TimeToLive 01:00:00 -ComputerName "AD1.bhc.sa"
Add-DnsServerResourceRecordA -Name "OneDrive" -ZoneName "bhc.sa" -AllowUpdateAny -IPv4Address "10.0.1.100" -TimeToLive 01:00:00 -ComputerName "AD1.bhc.sa"