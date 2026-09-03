# Networks: IPv4/IPv6 literals, CIDR prefix display, membership, ports,
# IPv4.of constructor.
#
# Cross-engine parity spec (scripts/parity.sh).

ip = 192.168.1.1
<< "ip [ip]"
<< "ip.type [type(ip)]"
<< "ip.port [10.0.0.1:8080]"
net = 10.0.0.0/8
<< "net [net]"
<< "net.type [type(net)]"
<< "net.prefix [net.prefix]"
<< "net24 [192.168.0.0/24]"
<< "net.include [net.include?(10.1.2.3)]"
<< "net.contains [net.contains?(11.1.2.3)]"
<< "net24.include [(192.168.0.0/24).include?(192.168.0.77)]"
<< "of [IPv4.of(192, 0, 2, 1)]"
<< "of.prefix [IPv4.of(192, 0, 2, 1, 24)]"
<< "of.prefix.val [IPv4.of(192, 0, 2, 1, 24).prefix]"
<< "octets [IPv4.of(192, 0, 2, 1).octets]"
<< "with_prefix [ip.with_prefix(16)]"
<< "cidr? [net.cidr?] [ip.cidr?]"
<< "eq [192.168.1.1 == 192.168.1.1]"
<< "v6 [2001:db8::1]"
<< "v6.net [2001:db8::/32]"
<< "v6.prefix [(2001:db8::/32).prefix]"
<< "v6.include [(2001:db8::/32).include?(2001:db8::1)]"
<< "zero [0.0.0.0/0]"
<< "tos [(10.0.0.0/8).to_s]"
<< net
