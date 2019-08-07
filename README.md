KNI-Preflight is a script that does some basic validation checks and generates the ironic_hosts.json file needed for a KNI install of OCP4 on baremetal nodes.

Example Output:

# ./kni-preflight.sh 
Discovering Cluster Name and Domain...
Access to RedFish enabled BMC: Success
Generation of Ironic JSON: Success
                                                                             
DiscoveryName              DiscoveryValues                                     
--------------------       ---------------------                               
Hostname_Long:             provisioner.rna1.example.com                        
Hostname_Short:            provisioner                                         
Clustername:               rna1                                                
Domain:                    example.com                                         
                                                                             
Hostname                   MacAddress                    IpAddress             Status
--------------------       --------------------          --------------------  --------------------
api.rna1.example.com       NA                            192.168.251.145       Success
*.apps.rna1.example.com    NA                            192.168.251.141       Success
ns1.rna1.example.com       NA                            192.168.251.145       Success
master-0.rna1.example.com  98:03:9B:61:88:41             192.168.251.142       Success
master-1.rna1.example.com  98:03:9B:61:88:11             192.168.251.143       Success
master-2.rna1.example.com  98:03:9B:61:6E:D9             192.168.251.144       Success

