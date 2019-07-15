#!/bin/bash
##################################################################
# This script generates the KNI Configuration files for a deploy #
##################################################################
#echo Enter master-0 iDRAC IP address:
#read master0
#echo Enter master-1 iDRAC IP address:
#read master1
#echo Enter master-2 iDRAC IP address:
#read master2
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

#bootstrapip=`ip addr show baremetal| grep 'inet ' | cut -d/ -f1 | awk '{ print $2}'`
bootstrapip=10.19.140.56
dnsname=`nslookup $bootstrapip|grep name| cut -d= -f2|sed s'/^ //'g|sed s'/.$//g'`
hostname=`echo $dnsname|awk -F. {'print $1'}`
clustername=`echo $dnsname|awk -F. {'print $2'}`
domain=`echo $dnsname|sed "s/$hostname.//g"|sed "s/$clustername.//g"`
apivip=api.$clustername.$domain
echo DNS Name: $dnsname
echo Hostname: $hostname
echo Cluster Name: $clustername
echo Domain: $domain
echo API Name: $apivip
if (getent hosts $apivip >/dev/null 2>&1); then
  echo API Name Exists: Yes
else 
  echo API Name Exists: Failed; exit
fi

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

ansible-playbook -i hosts redfish.yml

##################################################################
# Run make_ironic.yml Playbook					 #
##################################################################

ansible-playbook -i hosts make_ironic_json.yml
