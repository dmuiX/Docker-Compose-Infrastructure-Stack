# Architecture

## SplitDNS

everything domain.org goes to samba-dc
everyting fritx.box goes to 192.168.178.1/fritbox
everything else to 192.168.178.253

but DNS is always 192.168.178.253/pihole3

## renewal-hooks

certs are copied automatically when the cert is renewed!
