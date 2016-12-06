#!/bin/bash

echo "d4 net_reset.sh: Resetting network rules for D4 Demo VPN server..."

echo 1 > /proc/sys/net/ipv4/ip_forward

myaddress=$(hostname -I | cut -d" " -f1)
if [ -z "${myaddress}" ]; then
	echo "Could not find my ip address?"
	exit 1
fi
echo "d4 net_reset.sh: myaddress=${myaddress}"

iptables -F
iptables -P INPUT ACCEPT

# For testing, allow forwarding for all...
#iptables -P FORWARD ACCEPT

# But for security, block forwarding unless explicitly allowed in
# the rules that are added when ipsec vpn is established...
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT
iptables -A INPUT -p tcp --dport ssh -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

iptables -t nat -F
iptables -t nat -P PREROUTING ACCEPT
iptables -t nat -P INPUT ACCEPT
iptables -t nat -P OUTPUT ACCEPT
iptables -t nat -P POSTROUTING ACCEPT
iptables -t nat -A POSTROUTING -o ens3 -m policy --dir out --pol ipsec -j ACCEPT
iptables -t nat -A POSTROUTING -o ens3 -j SNAT --to-source ${myaddress}

# For DNS requests originating from a cellular connection, the DNS server is
# unlikely to be visible from here. Therefore, redirect to a DNS server that
# is accessible. These rules do blanket DNS redirection no matter the origin.
iptables -t nat -A PREROUTING --protocol udp -m udp --dport 53 -j DNAT --to 8.8.8.8
iptables -t nat -A PREROUTING --protocol tcp -m tcp --dport 53 -j DNAT --to 8.8.8.8

conntrack -F

# Workaround for sites that do not accept PMTU ICMP replies by hard coding a small MSS.
# Obviously this only works for TCP.
# If an app like VOIP specifically requests a small mss then we allow that. Otherwise large mss are rewritten.
# The value of the set-mss should be the smallest MTU of the links in the connection, subtract ESP overhead.
iptables -t mangle -F
iptables -t mangle -A FORWARD -p tcp -m tcp --tcp-flags SYN,RST SYN -m tcpmss --mss 1301:9999 -j TCPMSS --set-mss 1300

iptables -t raw -F
