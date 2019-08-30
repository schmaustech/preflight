#!/bin/bash
##################################################################
# This script generates the KNI Configuration files for a deploy #
##################################################################
##################################################################
# Set master iDRAC IP addresses & Username/Password for iDRAC    #
##################################################################

howto(){
  echo "Usage: kni-preflight -u username -p password -m master-0-ip,master-1-ip,master-2-ip -w worker-0-ip,worker-1-ip"
  echo "Example: kni-preflight -u root -p calvin -m 172.22.0.231,172.22.0.232,172.22.0.233 -w 172.22.0.234"
  echo "Example: kni-preflight -u root -p calvin -d"
}

df=0
while getopts u:p:m:w:dh option
do
case "${option}"
in
u) dracuser=${OPTARG};;
p) dracpassword=${OPTARG};;
m) mip=${OPTARG};;
w) wip=${OPTARG};;
d) df=1;;
h) howto; exit 0;;
\?) howto; exit 1;;
esac
done

KNIUSER=`who am i|awk {'print $1'}`
export KNIUSER
chmod 755 check_dhcp.py

if [ $KNIUSER == "root" ]; then
   echo "KNI-Preflight cannot be run as root and must use sudo"; exit 1
fi

if ([ -z "$dracuser" ] || [ -z "$dracpassword" ] || [ -z "$mip" ]  || [ -z "$wip" ] && [ "$df" -eq "0" ]) then
   howto
   exit 1
fi

if ([ -z "$dracuser" ] && [ "$df" -eq "1" ]) then
   dracuser="root"
fi

if ([ -z "$dracpassword" ] && [ "$df" -eq "1" ]) then
   dracpassword="calvin"
fi

if ([ -z "$mip" ] && [ "$df" -eq "1" ]) then
   mip="172.22.0.231,172.22.0.232,172.22.0.233"
fi

if ([ -z "$wip" ] && [ "$df" -eq "1" ]) then
   wip="172.22.0.234"
fi

if ([ "$df" -eq "1" ]) then
   dfstatus="Using defaults where no arguments provided..."
else
   dfstatus="Using user supplied arguments..."
fi

IFS=', ' read -r -a mipaddresses <<< "$mip"
IFS=', ' read -r -a wipaddresses <<< "$wip"

if ([ "${#mipaddresses[@]}" -ne "3" ]) then
   echo "3 master nodes must be defined.  Please try again."
   exit 1
fi

if [ "${#wipaddresses[@]}" -lt "1" ]; then
   echo "There needs to be at least 1 worker node defined.  Please try again."
   exit 1
fi

##################################################################
# Grab cluster and domain from discovery			                   #
##################################################################

echo Discovering Cluster Name and Domain...
bootstrapip=`ip addr show baremetal| grep 'inet ' | cut -d/ -f1 | awk '{ print $2}'`
dnsname=`nslookup $bootstrapip|grep name| cut -d= -f2|sed s'/^ //'g|sed s'/.$//g'`
hostname=`echo $dnsname|awk -F. {'print $1'}`
clustername=`echo $dnsname|awk -F. {'print $2'}`
domain=`echo $dnsname|sed "s/$hostname.//g"|sed "s/$clustername.//g"`
echo "###">dhcps
echo "DiscoveryName  DiscoveryValues">>dhcps
echo "--------------------  ---------------------">>dhcps
echo "Hostname_Long: $dnsname">>dhcps
echo "Hostname_Short: $hostname">>dhcps
echo "Clustername: $clustername">>dhcps
echo "Domain: $domain">>dhcps
echo "###">>dhcps

##################################################################
# Build initial inventory file					                         #
##################################################################

echo $dfstatus
echo "Building initial host inventory file..."
echo [bmcs]>hosts
c=0
for ipaddr in "${mipaddresses[@]}"
do
   echo "master-$c bmcip=$ipaddr">>hosts
   c=$((c+1))
done
c=0
for ipaddr in "${wipaddresses[@]}"
do
   echo "worker-$c bmcip=$ipaddr">>hosts
   c=$((c+1))
done
echo [bmcs:vars]>>hosts
echo bmcuser=$dracuser>>hosts
echo bmcpassword=$dracpassword>>hosts
echo domain=$domain>>hosts
echo cluster=$clustername>>hosts

#################################################################
# Determine External Network CIDR                               #
#################################################################

BARNET=`/usr/bin/ipcalc -n "$(/usr/sbin/ip -o addr show|grep baremetal|grep -v inet6|awk {'print $4'})"|cut -f2 -d=`
BARCIDR=`/usr/bin/ipcalc -p "$(/usr/sbin/ip -o addr show|grep baremetal|grep -v inet6|awk {'print $4'})"|cut -f2 -d=`
echo '[bootstrap]'>>hosts
echo localhost>>hosts
echo '[bootstrap:vars]'>>hosts
echo extcidrnet=$BARNET/$BARCIDR>>hosts
echo numworkers=0>>hosts
echo nummasters=3>>hosts

##################################################################
# Determine provisioning interface and baremetal interface       #
##################################################################

int_if=""
pro_if=""
lshw -class network | grep -A 1 "bus info" | grep name | awk -F': ' '{print $2}'|grep e | while read interface; do
if (`ip a|grep $interface|grep baremetal>/dev/null 2>&1`); then
        echo "intif=$interface">>hosts
        int_if="$interface"
elif (`ip a|grep $interface|grep provisioning>/dev/null 2>&1`); then
        echo "proif=$interface">>hosts
        pro_if="$interface"
else
        if ((`ip addr show $interface| grep -o "inet [0-9]*\.[0-9]*\.[0-9]*\.[0-9]*" | grep -o "[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*">/dev/null 2>&1`) && (`ip link show $interface|grep "state UP">/dev/null 2>&1`) && [[ $int_if == "" ]]); then
                echo "intif=$interface">>hosts
                int_if="$interface"
        fi
        if ((! `ip addr show $interface| grep -o "inet [0-9]*\.[0-9]*\.[0-9]*\.[0-9]*" | grep -o "[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*">/dev/null 2>&1`) && (`ip link show $interface|grep "state UP">/dev/null 2>&1`) && [[ $pro_if == "" ]] ); then
                echo "proif=$interface">>hosts
                 pro_if="$interface"
        fi
fi
done

##################################################################
# Run redfish.yml Playbook				                            	 #                                                              
################################################################## 

if (ansible-playbook -i hosts redfish.yml >/dev/null 2>&1); then
  echo Access to RedFish enabled BMC: Success
else
  echo Access to RedFish enabled BMC: Failed; exit 1
fi

##################################################################
# Run make_ironic.yml Playbook				                        	 #
##################################################################

if (ansible-playbook -i hosts make_ironic_json.yml >/dev/null 2>&1); then
  echo Generation of Ironic JSON: Success
else
  echo Generation of Ironic JSON: Failed; exit 1
fi

##################################################################
# Run Make Install Config Playbook                               #
##################################################################

if [ -f install-config.yaml ]; then
  cp -f install-config.yaml install-config.yaml.orig
fi
if (ansible-playbook -i hosts make-install-config.yml >/dev/null 2>&1); then
  echo Generation of Install Config Yaml: Success
else
  echo Generation of Install Config Yaml: Failed; exit 1
fi

##################################################################
# Run Make Config User Playbook                                  #
##################################################################

if (ansible-playbook -i hosts make_config_user.yml >/dev/null 2>&1); then
  echo Generation of Config_user.sh: Success
else
  echo Generation of Config_user.sh: Failed; exit 1
fi

##################################################################
# Add pullsecret to install-config.yaml                          #
##################################################################

PULLSECRET=pullsecret.txt
if [ -f "$PULLSECRET" ]; then
   sed -i "s/^'//" $PULLSECRET
   sed -i "s/'$//" $PULLSECRET 
   sed -i "s/PULLSECRETHERE/$(sed 's:/:\\/:g' $PULLSECRET)/" install-config.yaml
   sed -i "s/PULLSECRETHERE/$(sed 's:/:\\/:g' $PULLSECRET)/" config_$KNIUSER.sh
   python -c 'import yaml, sys; yaml.safe_load(sys.stdin)' < install-config.yaml
   if [ $? -ne 0 ]; then
      echo "Pullsecret addition to install-config.yaml: Failed"; exit 1
   else
      echo "Pullsecret addition to install-config.yaml: Success"
   fi
else
   echo "Pullsecret addition to install-config.yaml: Failed - Missing pullsecret file"; exit 1
fi

##################################################################
# Add sshkey to install-config.yaml                              #
##################################################################

SSHKEY=sshkey
DEFSSHKEY=/home/$KNIUSER/.ssh/id_rsa.pub
if [ -f "$SSHKEY" ]; then
   ssh-keygen -l -f $SSHKEY >/dev/null 2>&1
   if [ $? -ne 0 ]; then
      echo "SSHkey addition to install-config.yaml: Failed"; exit 1
   fi
   echo "SSHkey addition to install-config.yaml: User Supplied"
   sed -i "s/SSHKEYHERE/$(sed 's:/:\\/:g' $SSHKEY)/" install-config.yaml
   python -c 'import yaml, sys; yaml.safe_load(sys.stdin)' < install-config.yaml
   if [ $? -ne 0 ]; then
      echo "SSHkey addition to install-config.yaml: Failed"; exit 1
   else
      echo "SSHkey addition to install-config.yaml: Success"
   fi
else
   if [ -f "$DEFSSHKEY" ]; then
      ssh-keygen -l -f $DEFSSHKEY >/dev/null 2>&1
      if [ $? -ne 0 ]; then
         echo "SSHkey addition to install-config.yaml: Failed"; exit 1
      fi
      echo "SSHkey addition to install-config.yaml: Using Default"
      sed -i "s/SSHKEYHERE/$(sed 's:/:\\/:g' $DEFSSHKEY)/" install-config.yaml
      python -c 'import yaml, sys; yaml.safe_load(sys.stdin)' < install-config.yaml
      if [ $? -ne 0 ]; then
         echo "SSHkey addition to install-config.yaml: Failed"; exit 1
      else
         echo "SSHkey addition to install-config.yaml: Success"
      fi
   else
      echo "SSHkey addition to install-config.yaml: Failed - No Key Found"; exit 1
   fi
fi

##################################################################
# Print Out DHCP/DNS Scope				                             	 #
##################################################################

column -t dhcps | sed 's/###/ /g'

##################################################################
# Since we ran as sudo cleanup file perms
##################################################################

chown $KNIUSER:$KNIUSER ./*
