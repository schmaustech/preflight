#!/bin/bash
##################################################################
# This script generates the KNI Configuration files for a deploy #
##################################################################
##################################################################
# Set master iDRAC IP addresses & Username/Password for iDRAC    #
##################################################################

master0=172.22.0.151
master1=172.22.0.152
master2=172.22.0.153
dracuser=root
dracpassword=calvin

##################################################################
# Grab cluster and domain from discovery			 #
##################################################################

echo Discovering Cluster Name and Domain...
bootstrapip=`ip addr show baremetal| grep 'inet ' | cut -d/ -f1 | awk '{ print $2}'`
dnsname=`nslookup $bootstrapip|grep name| cut -d= -f2|sed s'/^ //'g|sed s'/.$//g'`
hostname=`echo $dnsname|awk -F. {'print $1'}`
clustername=`echo $dnsname|awk -F. {'print $2'}`
domain=`echo $dnsname|sed "s/$hostname.//g"|sed "s/$clustername.//g"`
echo " ">dhcps
echo "DiscoveryName  DiscoveryValues">>dhcps
echo "--------------------  ---------------------"
echo "Hostname_Long: $dnsname">>dhcps
echo "Hostname_Short: $hostname">>dhcps
echo "Clustername: $clustername">>dhcps
echo "Domain: $domain">>dhcps
echo " ">>dhcps

##################################################################
# Build initial inventory file					 #
##################################################################

echo [bmcs]>hosts
echo master-0 bmcip=$master0>>hosts
echo master-1 bmcip=$master1>>hosts
echo master-2 bmcip=$master2>>hosts
echo [bmcs:vars]>>hosts
echo bmcuser=$dracuser>>hosts
echo bmcpassword=$dracpassword>>hosts
echo domain=$domain>>hosts
echo cluster=$clustername>>hosts

##################################################################
# Run redfish.yml Playbook					 #                                                              
################################################################## 

if (ansible-playbook -i hosts redfish.yml >/dev/null 2>&1); then
  echo Access to RedFish enabled BMC: Success
else
  echo Access to RedFish enabled BMC: Failed; exit
fi


##################################################################
# Run make_ironic.yml Playbook					 #
##################################################################

if (ansible-playbook -i hosts make_ironic_json.yml >/dev/null 2>&1); then
  echo Generation of Ironic JSON: Success
else
  echo Generation of Ironic JSON: Failed; exit
fi

##################################################################
# Cat Out DHCP/DNS Scope					 #
##################################################################

column -t dhcps
