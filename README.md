# xenyth-dns-tools

An acme.sh dns-01 hook for [xenyth cloud](https://xenyth.net) dns

Requires jq

Usage:

- put `dns_xenyth.sh` within the `dnsapi` folder of `acme.sh`
- export `XENYTH_API_KEY` with your xenyth cloud API key (obtained by opening a ticket -- there is no public API and therefore no public API keys). This is only needed for the first run, it will be stored by acme.sh on renewal
- use acme.sh as you normally would with the `--dns dns_xenyth` argument.