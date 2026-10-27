"""Offline fixtures; these tests do not deploy or establish Azure network behaviour."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from test_probe import FAKE_CURL

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('service_config',ROOT/'scripts/check-service-config.py')
config=importlib.util.module_from_spec(spec)
spec.loader.exec_module(config)
SUBNET='/subscriptions/example/resourceGroups/lab/providers/Microsoft.Network/virtualNetworks/vnet/subnets/client'

class ServiceProbeTests(unittest.TestCase):
    def run_probe(self,mode,dns,status):
        with tempfile.TemporaryDirectory() as directory:
            folder=Path(directory)
            for name,body in [('curl',FAKE_CURL),('getent','#!/bin/sh\nprintf "%s STREAM fixture\\n" "$DNS_IP"\n')]:
                file=folder/name;file.write_text(body);file.chmod(0o755)
            env=dict(os.environ,PATH=directory+os.pathsep+os.environ['PATH'],DNS_IP=dns,NORMAL_STATUS=status,FORCED_STATUS='200')
            result=subprocess.run(['bash',str(ROOT/'scripts/service-probe.sh'),'stseabcd1234',mode],env=env,text=True,capture_output=True,timeout=10)
            self.assertNotIn('DO_NOT_LOG_THIS_TOKEN',result.stdout+result.stderr)
            return result
    def test_allowed_accepts_public_dns_and_authenticated_200(self):
        r=self.run_probe('allowed','20.60.1.2','200');self.assertEqual(r.returncode,0,r.stderr)
        self.assertIn('LAB_SERVICE_RESULT=PASS:',r.stdout)
    def test_denial_is_observation_not_root_cause_proof(self):
        r=self.run_probe('denied','20.60.1.2','403');self.assertEqual(r.returncode,0,r.stderr)
        self.assertIn('OBSERVED_DENY:',r.stdout);self.assertNotIn('LAB_SERVICE_RESULT=PASS:',r.stdout)
    def test_rbac_failure_does_not_pass_allowed_mode(self):
        r=self.run_probe('allowed','20.60.1.2','403');self.assertEqual(r.returncode,2)
    def test_private_dns_cannot_pass_even_when_http_is_200(self):
        r=self.run_probe('allowed','10.42.2.4','200');self.assertEqual(r.returncode,2)
    def test_mixed_dns_cannot_pass(self):
        r=self.run_probe('allowed','20.60.1.2\n10.42.2.4','200');self.assertEqual(r.returncode,2)
    def test_timeout_is_not_a_firewall_denial(self):
        r=self.run_probe('denied','20.60.1.2','000');self.assertEqual(r.returncode,2)
    def test_empty_dns_is_inconclusive(self):
        r=self.run_probe('allowed','','200');self.assertEqual(r.returncode,2)

class ServiceConfigurationTests(unittest.TestCase):
    def fixtures(self,allowed=True):
        return {'properties':{'publicNetworkAccess':'Enabled','allowSharedKeyAccess':False,'allowBlobPublicAccess':False,'networkAcls':{'defaultAction':'Deny','bypass':'None','ipRules':[],'virtualNetworkRules':[{'id':SUBNET,'action':'Allow'}] if allowed else []}}}, {'id':SUBNET,'serviceEndpoints':[{'service':'Microsoft.Storage','provisioningState':'Succeeded'}]}
    def test_accepts_restricted_allowed_and_denied_modes(self):
        for allowed in (True,False):
            with self.subTest(allowed=allowed): config.check(*self.fixtures(allowed),SUBNET,allowed)
    def test_rejects_missing_endpoint_despite_allow_rule(self):
        storage,subnet=self.fixtures();subnet['serviceEndpoints']=[]
        with self.assertRaises(ValueError):config.check(storage,subnet,SUBNET,True)
    def test_rejects_additional_public_ip_exception(self):
        storage,subnet=self.fixtures();storage['properties']['networkAcls']['ipRules']=[{'value':'8.8.8.8','action':'Allow'}]
        with self.assertRaises(ValueError):config.check(storage,subnet,SUBNET,True)
    def test_rejects_allow_all_default(self):
        storage,subnet=self.fixtures();storage['properties']['networkAcls']['defaultAction']='Allow'
        with self.assertRaises(ValueError):config.check(storage,subnet,SUBNET,True)
    def test_rejects_wrong_subnet_even_with_healthy_endpoint(self):
        storage,subnet=self.fixtures();subnet['id']=SUBNET+'other'
        with self.assertRaises(ValueError):config.check(storage,subnet,SUBNET,True)
    def test_rejects_disabled_public_endpoint_for_service_path(self):
        storage,subnet=self.fixtures();storage['properties']['publicNetworkAccess']='Disabled'
        with self.assertRaises(ValueError):config.check(storage,subnet,SUBNET,True)
    def test_rejects_rule_retained_in_denied_mode(self):
        with self.assertRaises(ValueError):config.check(*self.fixtures(),SUBNET,False)

route_spec=importlib.util.spec_from_file_location('service_route',ROOT/'scripts/check-service-route.py')
route=importlib.util.module_from_spec(route_spec)
route_spec.loader.exec_module(route)

class ServiceRouteTests(unittest.TestCase):
    def entry(self,prefix,hop='VirtualNetworkServiceEndpoint',state='Active'):
        return {'addressPrefix':[prefix],'nextHopType':hop,'state':state}
    def test_accepts_matching_service_route_over_internet_default(self):
        route.check({'value':[self.entry('0.0.0.0/0','Internet'),self.entry('20.60.0.0/16')]},'SERVICE_DNS=20.60.1.2\n')
    def test_unrelated_service_route_does_not_prove_path(self):
        with self.assertRaises(ValueError):route.check({'value':[self.entry('20.61.0.0/16'),self.entry('0.0.0.0/0','Internet')]},'SERVICE_DNS=20.60.1.2\n')
    def test_inactive_service_route_does_not_pass(self):
        with self.assertRaises(ValueError):route.check({'value':[self.entry('20.60.0.0/16',state='Invalid')]},'SERVICE_DNS=20.60.1.2\n')
    def test_all_dns_answers_need_service_routes(self):
        with self.assertRaises(ValueError):route.check({'value':[self.entry('20.60.0.0/16')]},'SERVICE_DNS=20.60.1.2,20.61.1.2\n')
    def test_ambiguous_guest_output_cannot_pass(self):
        with self.assertRaises(ValueError):route.check({'value':[self.entry('20.60.0.0/16')]},'SERVICE_DNS=20.60.1.2\nSERVICE_DNS=20.60.1.3\n')

if __name__=='__main__': unittest.main()
