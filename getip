#!/usr/bin/env python
import subprocess, re
co = subprocess.Popen(['ifconfig'], stdout = subprocess.PIPE)
ifconfig = co.stdout.read()
ip_regex = re.compile('((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-4]|2[0-5][0-9]|[01]?[0-9][0-9]?))')
ips = [match[0] for match in ip_regex.findall(ifconfig, re.MULTILINE)]
ips = [ip for ip in ips if '192' in ip and not ip.endswith('255')]
for ip in ips:
    print ip
