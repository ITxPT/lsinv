#!/bin/bash 
#####################################################################
#
#  ITxPT tools
#  lsinv.sh
#
#  Specification  :   2.x.x
#  Module         :   lsinv.sh
#  Description    :   list inventory in a specific IPv4 network.
#
#  Version        :   1.0  
#  Author         :   Lars Paape - lars.paape@itxpt.org
#  Date           :   15.03.2023 (dd.mm.yyyy)
#
#  All Rights Reserved - Copyright (c) 2023 - ITxPT
#  
#####################################################################
#
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

#check for necessary tools

LIST_OF_TOOLS="avahi-daemon avahi-browse grepcidr jq"
ERROR=0
for TOOL in ${LIST_OF_TOOLS[@]}
do
   command -v $TOOL &> /dev/null 
   if [[ $? != 0 ]]; then
    printf "\e[31mERROR: $TOOL not installed.\e[0m\n"
    ERROR=1
   fi
done
if [[ ERROR == 1 ]]; then
  exit 1
fi
# check avahi settings
#
AVAHI_IPV6=$(awk -F '='  '{if ($0 ~ /^use-ipv6/) {print $2}}' /etc/avahi/avahi-daemon.conf)

if [[ "${AVAHI_IPV6}" == "yes" ]]; then
   printf "\e[33mWARNING: ahavi-daemon IPv6 option enabled!\e[0m\n"
   printf "IP detection not reliablable if device in test uses IPv6 and IPv4.\n"
   printf "Change to \"use-ipv6=no\" in /etc/avahi/avahi-daemon.conf.\n"
   sleep 10
fi

# read out options
# c - CSV output
# w - list only inventories that implemnt _itxpt_http_._tcp
# s - list only inventories that implemnt _itxpt_socket_._tcp
# d - reset avahi-daemon, requires sudo and a settling time 
# i - IP network example 192.168.1.0/24
# h - help 

SETTLING_TIME=10
CSV_OUTPUT=0
AVAHI_RESET=0
HTTP_ONLY=0
SOCKET_ONLY=0
HELP=0
IP_ADDR=""

function optionsInfo(){
    echo "lsinv.sh - list available ITxPT inventories for the given "
    echo "Parameters:"
    echo "-i - [IP_NETWORK] - required"
    echo "-c - CSV output (default JSON) - WARNING: issues with unsorted and optional fields"
    echo "-w - only inventories that implement _itxpt_http_._tcp (optional)"
    echo "-s - only inventories that implement _itxpt_socket_._tcp (optional)"
    echo "-d - reset avahi-daemon, requires sudo and has a settling time of $SETTLING_TIME seconds"
    echo "-h - help"
    echo "Example: ./lsinv.sh  -i 192.168.1.0/24"
}

while getopts "chwsdi:" flag
do
    case "${flag}" in
        c) CSV_OUTPUT=1;;
        d) AVAHI_RESET=1;;
        w) HTTP_ONLY=1;;
        s) SOCKET_ONLY=1;;
        h) HELP=1;;
        i) IP_ADDR="${OPTARG}";;
    esac
done

if [[ $HELP == 1  || "$IP_ADDR" == "" ]]; then
      optionsInfo 
      exit 1
fi 
if [[ $HTTP_ONLY == 0  && $SOCKET_ONLY == 0 ]]; then
    HTTP_ONLY=1
    SOCKET_ONLY=1
fi

if [[ $AVAHI_RESET == 1 ]]; then 
    #check for sudo
    LUID=$(id -u) #get user id - root==0
    if [[ $LUID != 0 ]]; then 
        echo "sudo required to reset the avahi-daemon"
        exit 1
    fi
    printf "clear avahi cache and restart daemon \n"
    # make sure the mdns cache was reset
    service avahi-daemon restart 
    sleep 3
    avahi-browse -art > /dev/null # first request
    sleep 2
    avahi-browse -art > /dev/null # second request
    printf "%d seconds settling time\n" $SETTLING_TIME
    sleep $SETTLING_TIME
fi

# temp files
SOCKET_FILE=/tmp/socket_itxpt.txt
HTTP_FILE=/tmp/http_itxpt.txt
SINGLE_ENTRY_FILE=/tmp/single_entry.txt
JSON_FILE=/tmp/inventories.json

rm -f $SOCKET_FILE &> /dev/null
rm -f $HTTP_FILE &> /dev/null
rm -f $JSON_FILE &> /dev/null
rm -f $SINGLE_ENTRY_FILE &> /dev/null

avahi-browse -art &> /dev/null # first request
sleep 3
avahi-browse -art &> /dev/null # second request
sleep 3

LIST_OF_FILES=""
# socket
if [[ $SOCKET_ONLY == 1 ]]; then
    # filter for "_inventory" and entries that have an IPv4 address - main entries in avahi-browse
    avahi-browse -vrtp _itxpt_socket._tcp  | grep -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | grep "_inventory" > $SOCKET_FILE
    if [ ! -s  $SOCKET_FILE ]; then
       echo "No _itxpt_socket._tcp inventory found."
    else
       LIST_OF_FILES="$SOCKET_FILE "
    fi
fi
# http
if [[ $HTTP_ONLY == 1 ]]; then
    avahi-browse -vrtp _itxpt_http._tcp  | grep -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | grep "_inventory" > $HTTP_FILE
    if [ ! -s  $HTTP_FILE ]; then
       echo "No _itxpt_http._tcp inventory found."
    else
       LIST_OF_FILES="$LIST_OF_FILES $HTTP_FILE "
    fi
fi

# produce list
echo "[" > $JSON_FILE

GT1ENTRY=0
for INVENTORIES in ${LIST_OF_FILES[@]}
do
    IPS=$(more $INVENTORIES | cut -d ";" -f8)
    for IP in ${IPS[@]}
    do
      IP_RESULT=$(echo "$IP" | grepcidr $IP_ADDR)
      if [[ "$IP_RESULT" == "$IP" ]]; then
         #IP in the network
         if [[ $GT1ENTRY == 1 ]]; then
            echo "," >> $JSON_FILE
         fi
         rm -f $SINGLE_ENTRY_FILE &> /dev/null
         more $INVENTORIES | grep $IP > $SINGLE_ENTRY_FILE
         HOSTNAME=$(more $SINGLE_ENTRY_FILE | cut -d ";" -f7)
         IP_PORT=$(more $SINGLE_ENTRY_FILE | cut -d ";" -f9)
         more $SINGLE_ENTRY_FILE | cut -d ";" -f10- | awk -v HNAME="$HOSTNAME" -v IPADD="$IP" -v APORT="$IP_PORT" -f ${SCRIPT_DIR}/txt_to_json.awk >> $JSON_FILE

         GT1ENTRY=1
      fi
    done
done
echo "]" >> $JSON_FILE

if [[ $GT1ENTRY == 1 ]]; then
    if [[ $CSV_OUTPUT == 1 ]]; then
      cat $JSON_FILE | jq -r '.[]| join(",")'
    else
      more $JSON_FILE
    fi
fi