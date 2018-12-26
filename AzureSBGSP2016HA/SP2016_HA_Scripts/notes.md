# Sharepoint 2016 with azbb v2 and DSC

## Differences with the doc:

- I had to shorten the names on several of the VMs, so they no longer match the ones in the doc.


## Deployment order:

1. onprem.json (simulated onprem)

2. connections.json (azure vnet gateway and connection with onprem)

3. azure1.json (main azure infrastructure)

4. azure2-cluster.json  (create cluster and always on group and listener)

5. azure3.json (create the rest of the infraestructure)

    At this point you should check TCP connectivity between 'ra-sp-app-vm1' and 'ra-sp-sql-lb' on port 1433
    Otherwise reboot 'ra-sp-sql2-vm2'.

6. azure4-sharepoint-server.json (create sharepoint farm primary node)

    This extension sometimes fail but DSC keeps retrying and succeeds at installing the sharepoing farm.

7. azure5-sharepoint-farm.json (create sharepoint cache, search and web)

8. azure6-security.json (create network security groups)
