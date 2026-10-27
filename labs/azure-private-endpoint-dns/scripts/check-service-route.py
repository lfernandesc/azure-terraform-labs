#!/usr/bin/env python3
"""Match guest DNS answers to the NIC's active effective routes; fixtures do not call Azure."""
import ipaddress,json,re,sys

def check(routes,report):
    matches=re.findall(r'^SERVICE_DNS=([0-9.,]+)\s*$',report,re.M)
    if len(matches)!=1: raise ValueError('Missing or ambiguous guest DNS result')
    addresses=[ipaddress.IPv4Address(ip) for ip in matches[0].split(',')]
    if not addresses or not all(ip.is_global for ip in addresses): raise ValueError('Expected public service DNS answers')
    for address in addresses:
        candidates=[]
        for route in routes.get('value',[]):
            if route.get('state')!='Active': continue
            for prefix in route.get('addressPrefix',[]):
                net=ipaddress.ip_network(prefix,strict=False)
                if net.version==4 and address in net: candidates.append((net.prefixlen,route.get('nextHopType')))
        if not candidates: raise ValueError('No active effective route for '+str(address))
        longest=max(p for p,_ in candidates)
        if {hop for p,hop in candidates if p==longest}!={'VirtualNetworkServiceEndpoint'}:
            raise ValueError('Most-specific active route is not a service endpoint for '+str(address))

if __name__=='__main__':
    try:
        with open(sys.argv[1]) as f: routes=json.load(f)
        with open(sys.argv[2]) as f: report=f.read()
        check(routes,report)
    except (ValueError,KeyError,IndexError) as exc:
        print('SERVICE_ROUTE=FAIL: '+str(exc),file=sys.stderr);sys.exit(2)
    print('SERVICE_ROUTE=PASS: every guest DNS IPv4 answer matches an active VirtualNetworkServiceEndpoint route')
