#!/bin/bash

# Wrapper script to call outbound_connection_count.sh and do logging stuff
# author: Tuan Hoang
#
script_name=${0##*/}
function usage()
{
    echo "###Syntax: $script_name -t <threshold>"
    echo "- Without specifying -f <interval>, the script will execute every 10s"
    echo "- Without specifying -t <threshold>, the default will be 100"
    echo "###Threshold: when an instance has the number of outbound connections toward any destination reaches that threshold, the script will automatically take memory dump for that instance"
}
function die()
{
    echo "$1" && exit $2
}
function getcomputername()
{
    # $1-pid
    instance=$(cat "/proc/$1/environ" | tr '\0' '\n' | grep -w COMPUTERNAME)
    instance=${instance#*=}
    echo "$instance"
}
function getsasurl()
{
    # $1-pid
    sas_url=$(cat "/proc/$1/environ" | tr '\0' '\n' | grep -w DIAGNOSTICS_AZUREBLOBCONTAINERSASURL)
    sas_url=${sas_url#*=}
    echo "$sas_url"
}
while getopts ":t:f:h" opt; do
    case $opt in
        t) 
           threshold=$OPTARG
           ;;
        f)
           frequency=$OPTARG
           ;;
        h)
           usage
           exit 0
           ;;
        *) 
           die "Invalid option: -$OPTARG" 1 >&2
           ;;
    esac
done
shift $(( OPTIND - 1 ))

if [[ -z "$threshold" ]]; then
    echo "###Info: without specifying option -t <threshold>, the script will set the default outbound connection count to 100 before triggering memory dump taking"
    threshold=100
fi

if [[ -z "$frequency" ]]; then
    echo "###Info: without specifying option -f <interval>, the script will execute every 10s"
    frequency=10
fi

# Install net-tools if not exists
if ! command -v netstat &> /dev/null; then
    echo "###Info: netstat is not installed. Installing net-tools."
    apt-get update && apt-get install -y net-tools
fi

# Find the PID of the .NET application
pid=$(/tools/dotnet-dump ps | grep /usr/share/dotnet/dotnet | grep -v grep | tr -s " " | cut -d" " -f2)
if [ -z "$pid" ]; then
    die "There is no .NET process running" 1
fi

# Get the computer name from /proc/PID/environ, where PID is .net core process's pid
instance=$(getcomputername "$pid")
if [[ -z "$instance" ]]; then
    die "Cannot find the environment variable of COMPUTERNAME" >&2 1
fi

# Output dir is named after instance name
output_dir="outconn-logs-${instance}" 

# Create output directory if it doesn't exist
mkdir -p "$output_dir"

sas_url=$(getsasurl "$pid")

while true; do
    # Check if it's a new hour
    current_hour=$(date +"%Y-%m-%d_%H")
    if [ "$current_hour" != "$previous_hour" ]; then
        # Rotate the file
        output_file="$output_dir/outbound_conns_stats_${current_hour}.log"
        previous_hour="$current_hour"
    fi
    ./outbound_connection_count.sh "$threshold" "$instance" "$pid" "$sas_url" >> "$output_file"

    # Wait for 10 seconds before the next run
    sleep $frequency
done

