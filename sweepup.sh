#!/bin/bash
#
# Sweep devices for uptime.
# v2.2 - Unified DHMS formatting (via -Ot), SNMPCMD as array, clearer SNMP error highlighting
#
# use -f to specify input file of specific hostnames/FQDNs or IPs to poll
# use -l to specify a list of specific hostnames or IPs on the command line
# use -v3 to specify SNMPv3 (creds set below as they are a pain to type out)
# use -c to override the v2c community string
# use -s to check status of stackwise members
# use -e to use sysUpTime instead of snmpEngineTime
#
# eg: sweepup -v3 -l myfw01 myfw02 myfw03
#     sweepup lonplcasw
#     sweepup -f mylistofdevices.txt
#
trap "tput sgr0;echo;exit" SIGINT
USAGE="$0 {-v3} {-e} {-s} {-f filename} {-c community} {-l list of devices} {string}"
TIMEOUT=4		# 4 secs
RETRIES=0		# No retries
READSTR="public"	# v2c community
FILE=/etc/hosts		# Default file to search for resolution
V3USER="snmp-v3-user"	# Default SNMPV3 User
V3AUTH=SHA		# Default SNMPV3 Auth Mechanism
SNMPAUTH="V3AuthPW"	# SNMPv3 Auth Password
V3PRIV=AES		# Default SNMPV3 Priv Mechanism
SNMPPRIV="V3PrivPW"	# SNMPv3 Priv Password
SNMPVER=2c		# Default version = 2c
USEENGINE=1		# Use snmpEngineTime - sysUpTime wraps after 496 days
STACKSTATEOID=1.3.6.1.4.1.9.9.500.1.2.1.1.6
STACKS=0
PATTERN=""
LIST=()

# -Ot: print TimeTicks as a raw integer (centiseconds) instead of net-snmp's
# own "D:HH:MM:SS.ss" auto-formatting. This is what lets snmpEngineTime and
# sysUpTime share one formatter below instead of two divergent output styles.
SNMPCMD=(snmpget -On -Ot -t "$TIMEOUT" -r "$RETRIES" -c "$READSTR" -v"$SNMPVER")

# Shared uptime formatter. Both OIDs land here as a raw integer; `scale`
# accounts for snmpEngineTime being seconds vs sysUpTime being centiseconds.
DHMS_AWK='{ if ($1 ~ /^[0-9]+$/) { raw=$1; secs=raw/scale;
   printf(" (%d) %d days, %02d:%02d:%02d\n", raw, int(secs/86400), int(secs/3600)%24, int(secs/60)%60, int(secs)%60); exit }
   print $0; exit }'

tput sgr0

if [ "$#" -eq 0 ]; then
   echo "Usage: $USAGE"
   exit 1
fi

# Single while/case loop handles every case uniformly, whether it's one
# arg or many. -l is the only genuinely variadic flag: it slurps
# hostnames until it hits the next -flag or runs out of args, so no
# quoting gymnastics are needed on the command line.
while [ "$#" -gt 0 ]; do
   case "$1" in
      -v3)
         printf "Override: Using \033[31;1mSNMPv3\033[0m with credentials in script\n"
         SNMPCMD=(snmpget -On -Ot -t "$TIMEOUT" -r "$RETRIES" -v3 -u "$V3USER" -l authPriv -a "$V3AUTH" -A "$SNMPAUTH" -x "$V3PRIV" -X "$SNMPPRIV")
         shift
         ;;

      -c)
         shift
         if [ -z "$1" ]; then
            printf "Expected a community string after -c\n"
            exit 1
         fi
         printf "Override: Using \033[31;1mSNMPv2\033[0m with Community \033[37m%s\033[0m\n" "$1"
         READSTR="$1"
         SNMPCMD=(snmpget -On -Ot -t "$TIMEOUT" -r "$RETRIES" -c "$READSTR" -v"$SNMPVER")
         shift
         ;;

      -f)
         shift
         if [ -z "$1" ] || [ ! -r "$1" ]; then
            printf "File %s not readable or doesn't exist\n" "$1"
            exit 1
         fi
         printf "Using file \033[37m%s\033[0m for list of hosts to sweep\n" "$1"
         while IFS= read -r line; do
            [ -n "$line" ] && LIST+=("$line")
         done < <(grep -Ev '^$|^#' "$1")
         shift
         ;;

      -l)
         shift
         if [ "$#" -eq 0 ]; then
            printf "Expected hostnames after -l\n"
            exit 1
         fi
         printf "Using list provided from command line...\n"
         while [ "$#" -gt 0 ] && [[ "$1" != -* ]]; do
            LIST+=("$1")
            shift
         done
         ;;

      -s)
         STACKS=1
         shift
         ;;

      -e)
         printf "Override: Using \033[31;1msysUpTime\033[0m instead of snmpEngineTime\n"
         USEENGINE=0
         shift
         ;;

      -h|--help)
         echo "Usage: $USAGE"
         exit 0
         ;;

      -*)
         echo "Unknown option: $1"
         echo "Usage: $USAGE"
         exit 1
         ;;

      *)
         if [ -z "$PATTERN" ]; then
            PATTERN="$1"
         else
            printf "Use -l [node1] [node2] ... for multiple targets.\n"
            exit 1
         fi
         shift
         ;;
   esac
done

# If neither -l nor -f gave us a list, search $FILE for a pattern match
if [ "${#LIST[@]}" -eq 0 ]; then
   if [ -z "$PATTERN" ]; then
      echo "Usage: $USAGE"
      exit 1
   fi
   printf "Searching for \033[37m%s\033[0m in %s\n" "$PATTERN" "$FILE"
   while IFS= read -r line; do
      LIST+=("$line")
   done < <(grep -Ev '^#|^$' "$FILE" | grep -Ei "$PATTERN" | awk '{print $2}' | sort | uniq)
fi

# Print correct header in case of stacks option
if [ "$STACKS" == "1" ]; then
   printf "%-41s %-18s\n" " Device" "Ping Stack   Uptime"
else
   printf "%-41s %-12s\n" " Device" "Ping Uptime"
fi

for host in "${LIST[@]}"
   do
   printf "\033[37m %-8.8s \033[36;1m%-30.30s \033[37m:" "Req from" "$host"
    AVAIL=0
    ping -qc1 -W1 "$host" > /dev/null 2>&1
    case $? in
       0)   printf "\033[32;1m%s\033[0m" " OK " ; AVAIL=1 ;;
       1)   printf "\033[31;1m%s\033[0m" " NR " ;;
       *)   printf "\033[31;1m%s\033[0m\n" " UH  Unresolvable Host" ; continue ;;
    esac

    # If requested, check for stackwise switches being up
    if [ "$STACKS" == "1" ] ; then
       SWSUP=$("${SNMPCMD[@]}" "$host" "$STACKSTATEOID" 2>/dev/null |\
              awk 'BEGIN{ORS="\n";members=0;membok=0}
              NF ~/^[0-9]$/ {members++ ; swid=substr($1, length($1)-3)} ;
              NF == 4 { membok++ ;next }
              END { if ( membok == members && members > 0 ) printf  "\033[32;1m"membok"/"members"\033[0m"
                    else if ( membok < members )printf "\033[31;1m"membok"/"members"\033[0m"
                    else printf "\033[37mN/A\033[0m"}')
       printf " [$SWSUP] "
    fi

    if [ "$USEENGINE" -eq "1" ]; then
       # snmpEngineTime is INTEGER seconds - not affected by -Ot, no scaling needed
       UPTIME=$("${SNMPCMD[@]}" "$host" .1.3.6.1.6.3.10.2.1.3.0 2>&1 | head -1 | sed 's/^\..*: //g' | awk -v scale=1 "$DHMS_AWK")
    else
       # sysUpTime is TimeTicks centiseconds - -Ot forces raw output, scale down by 100
       UPTIME=$("${SNMPCMD[@]}" "$host" 1.3.6.1.2.1.1.3.0 2>&1 | head -1 | sed 's/^\..*= //g' | awk -v scale=100 "$DHMS_AWK")
    fi
    # awk program to format based upon response or uptime
    echo "$UPTIME" |  awk '$2 ~/^[0-9]+$/ && $2 == 0 {print "\033[31;1m"$0"\033[0m"; exit}
           $2 ~/^[0-9]+:[0-9]*/ {print "\033[31;1m"$0"\033[0m"; exit}
           $2 ~/^[0-9]+$/ && $2 == 1 {print "\033[35;1m"$0"\033[0m"; exit}
           $2 ~/^[0-9]+$/ && $2 >= 2 && $2 <=7 {print "\033[36;1m"$0"\033[0m"; exit}
           $2 ~/^[0-9]+$/ && $2 > 7 && $2 < 1000 {print "\033[32;1m"$0"\033[0m"; exit}
           $2 ~/^[0-9]+$/ && $2 >= 1000  {print "\033[32;1m"$0"\033[0m \033[36;1m[WOW!]\033[0m"; exit}
           /No Response/ {print "\033[31;1m"$0"\033[0m"; exit}
           /Timeout/ {print "\033[31;1m No Response - Timeout\033[0m"; exit}
           /Unknown user name|Authentication failure|wrong (SNMP|USM)|Wrong Type|noSuchObject|noSuchInstance/ {print "\033[31;1m"$0"\033[0m"; exit}
           /system.sysUpTime.0/ {print "\033[31;1m No Such Host\033[0m"; exit}
           { print "\033[34;1m"$0" \033[0m"}'

done
tput sgr0
