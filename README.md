# Netscripts

This is a selection of portable bash scripts used for network
support/engineering purposes. These were originally written many moons
Chatago but have been reviewed/refactored with GPT/Claude to fix some
bugs and to add new features which has saved my aging brain some work.

- fullportstatus:   Quick status of all ports on a device
- traceparse:       Resolve hops from Cisco/Juniper traceroute output via SNMP/DNS
- sweepup:          Sweep uptime of devices + stack status if desired
- hwaudit:          Sweep name, uptime, stack status, PSU/Fan Status, software version
- iping:            Continuous pinger for monitoring intermittent issues
- tls-audit:        TLS audit for supported ciphers on endpoints

Use at your own risk etc etc, no liability accepted.

## fullportstatus

By running this with -n you can audit a bunch of devices before and after major works
to make sure things look the same. Eg:

```text
for host in 192.168.122.{2..3}; 
do echo "=== $host ==="; ./fullportstatus -n "$host" ; done | tee port-audit-before.txt
```

Repeating the above with a port-audit-after.txt then lets you do:

```text
vimdiff port-audit-before.txt port-audit-after.txt
```

Usage Details:

```text
Usage: ./fullportstatus [options] devicename
       ./fullportstatus [options] -h devicename

Options:
 -3          use SNMPv3 creds set in script
 -l          use low-speed ifSpeed OID for older devices
 -n          do not colourise
 -f 'regex'  show only interfaces whose ifDescr matches regex
 -h name     specify hostname

The -f option accepts a POSIX awk extended regular expression.
Quoting the expression is recommended to prevent shell expansion.

Examples:
  ./fullportstatus router1
  ./fullportstatus -n router1
  ./fullportstatus router1 -f '^GigabitEthernet'
  ./fullportstatus -f '^ge-' router2
  ./fullportstatus -f '^ge-[0-9]+/[0-9]+/[0-9]+$' router2
```

![fullportstatus](images/fullportstatus.png)

## traceparse

Resolve hops in Cisco/Juniper traceroute output by snmp SysName.0 or
via DNS.

Handy for when name resolution isn't configured on network kit.

Just paste your traceroute output in, and hit ENTER twice - 2 x empty
lines start resolving.

```text
Usage: traceparse [options]

Options:
    -m METHOD       Resolution method: snmp or dns
                    Default: snmp

    -c COMMUNITY    SNMP v2c community string
                    Default: public

    -s DNS_SERVER   DNS server to use for reverse lookups.
                    Only valid with '-m dns'.

    -h              Display this help.

Examples:
    traceparse
    traceparse -m snmp -c public
    traceparse -m dns
    traceparse -m dns -s 192.0.2.53
```

## sweepup

Sweep Uptime of multiple devices to check for reboots and reachability.

```text
Usage: ./sweepup [options] -l target1 target2  ...
       ./sweepup [options] search-string

Options:
 -v3                  Use SNMPv3 with credentials set in script
 -c COMMUNITY         Override default SNMPv2C community string
 -e                   Use sysUpTime instead of snmpEngineTime
 -f FILENAME          Search device names from a hosts style file
 -l device1 device2   Specify list of devices to sweep
 -s                   Try to verify status of Cisco Stack members

 If using IPs or FQDNs, specify with a list after -l
 If wanting to just search within a hosts style file, use a string or regex

Examples:
  ./sweepup router[123]
  ./sweepup -f /etc/hosts lon
  ./sweepup -c READONLY -l router1.lab.local
  ./sweepup -s -l 192.168.122.2 192.168.122.3
  ./sweepup -l router{1..8}.lab.local
```

![sweepup](images/sweepup.png)


## hwaudit

Sweep devices for more detailed info, see screenshot below. Stacks can also be
included if desired to check stack members in ready state.

Useful for checking after power/cabing/upgrade works to check versions and PSU/FAN
statuses.

See --help for full info. Filling out default strings in script will make life easier.

```text
Examples:
  hwaudit -c COMMUNITY \
      --hosts host1.lab.local host2.lab.local

  SNMP_COMMUNITY='COMMUNITY' \
      hwaudit --host-file switches.txt

  hwaudit -v 3 \
      -u snmp-readonly \
      -l authPriv \
      -a SHA \
      -A 'authentication-password' \
      -x AES \
      -X 'privacy-password' \
      --hosts host1.lab.local

  hwaudit -c COMMUNITY \
      --no-color \
      --host-file switches.txt > results.txt
```

![sweepup](images/hwaudit.png)

## iping

Monitor a host for intermittent packet loss and latency.

```text
Usage: iping [options] HOST

Options:
  -4              Force IPv4
  -6              Force IPv6
  -c COUNT        Stop after COUNT probes
  -i SECONDS      Interval between probes (default: 1)
  -W SECONDS      Reply timeout (default: 1)
  -o FILE         Log failures/events to FILE
  -q              Quiet mode; don't print successful probes
  -n              Use numeric ping output
  -h              Show this help

Examples:
  iping router.example.com
  iping -c 100 192.0.2.1
  iping -i 5 -W 2 router.example.com
  iping -q -o flaky.log router.example.com
  iping -6 2001:db8::1
```

![iping](images/iping.png)


## tls-audit

TLS Testing Tool.

```text
Usage:
  tls-audit [options] <hostname> [port]

Options:
  -s, --summary       Show summary only
  -j, --json          Output JSON
  -c, --csv           Output CSV
      --no-delay      Do not pause between cipher tests
      --no-colour     Disable coloured output
      --no-color      Same as --no-colour
  -h, --help          Show this help

Environment:
  OPENSSL=/path       OpenSSL binary to use
  DELAY=seconds       Delay between cipher tests (default: 0.1)

Examples:
  tls-audit example.com
  tls-audit example.com 8443
  tls-audit --summary example.com
  tls-audit --json example.com > result.json
  tls-audit --csv example.com > result.csv

Exit codes:
  0   Scan completed; no audit issues detected
  1   Scan completed; audit issues detected
  2   Connection or TLS handshake failed
  3   Usage/local dependency error
```

Normal Mode:
![iping](images/tls-audit0.png)

Summary Mode:
![iping](images/tls-audit.png)
