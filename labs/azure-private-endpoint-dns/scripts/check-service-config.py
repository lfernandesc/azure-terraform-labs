#!/usr/bin/env python3
"""Validate live ARM settings, not Terraform's intention. No cloud calls here."""
import json,sys

def check(storage, subnet, expected_subnet, allowed):
    p=storage.get('properties',{})
    acl=p.get('networkAcls',{})
    rules=acl.get('virtualNetworkRules',[])
    if p.get('publicNetworkAccess')!='Enabled' or p.get('allowSharedKeyAccess') is not False:
        raise ValueError('Comparison account must use public networking with Shared Key disabled')
    if p.get('allowBlobPublicAccess') is not False or acl.get('defaultAction')!='Deny' or acl.get('bypass')!='None':
        raise ValueError('Anonymous access or firewall default/exception differs from the lab')
    if acl.get('ipRules') or acl.get('resourceAccessRules'):
        raise ValueError('Unexpected public IP or resource instance exceptions')
    actual=[(r.get('id','').lower(),r.get('action')) for r in rules]
    expected=[(expected_subnet.lower(),'Allow')] if allowed else []
    if actual!=expected:
        raise ValueError('Subnet allow rules differ from expected mode')
    if subnet.get('id','').lower()!=expected_subnet.lower():
        raise ValueError('Wrong subnet inspected')
    if not any(e.get('service')=='Microsoft.Storage' and e.get('provisioningState')=='Succeeded' for e in subnet.get('serviceEndpoints',[])):
        raise ValueError('Microsoft.Storage endpoint is not provisioned on the client subnet')

if __name__=='__main__':
    try:
        with open(sys.argv[1]) as f: storage=json.load(f)
        with open(sys.argv[2]) as f: subnet=json.load(f)
        check(storage,subnet,sys.argv[3],sys.argv[4]=='allowed')
    except (ValueError,KeyError,IndexError) as exc:
        print('SERVICE_CONFIG=FAIL: '+str(exc),file=sys.stderr)
        sys.exit(2)
    print('SERVICE_CONFIG=PASS: live ARM settings match the selected mode')
