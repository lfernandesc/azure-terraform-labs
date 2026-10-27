"""Verify that a successful first direction or Azure API alone cannot pass the suite."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]
FAKE_TERRAFORM = '''#!/usr/bin/env python3
import json,sys
values={'resource_group':'rg-test','vm_names':{'spoke-a':'vm-spoke-a','spoke-b':'vm-spoke-b'},'node_ips':{'spoke-a':'10.51.0.4','spoke-b':'10.52.0.4'}}
value=values[sys.argv[-1]]
print(json.dumps(value) if isinstance(value,dict) else value)
'''
FAKE_AZ = '''#!/usr/bin/env python3
import os,sys
args=sys.argv[1:];vm=args[args.index('--name')+1]
with open(os.environ['CALL_LOG'],'a') as log:log.write(vm+'\\n')
print('LAB_RESULT=INCONCLUSIVE: fixture' if os.environ.get('FAIL_SECOND')=='1' and vm=='vm-spoke-b' else 'LAB_RESULT=PASS: fixture')
'''
class RunnerTests(unittest.TestCase):
    def runner(self, fail_second):
        with tempfile.TemporaryDirectory() as folder:
            for name,code in [('terraform',FAKE_TERRAFORM),('az',FAKE_AZ)]:
                file=Path(folder)/name;file.write_text(code);file.chmod(0o755)
            log=Path(folder)/'calls'
            env=dict(os.environ,PATH=folder+os.pathsep+os.environ['PATH'],CALL_LOG=str(log),FAIL_SECOND=str(int(fail_second)))
            result=subprocess.run(['bash','scripts/run-probe.sh','fixed'],cwd=ROOT,env=env,text=True,capture_output=True,timeout=15)
            calls=log.read_text().splitlines()
            return result,calls
    def test_runs_both_spokes(self):
        result,calls=self.runner(False)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(calls,['vm-spoke-a','vm-spoke-b'])
        self.assertIn('LAB_SUITE=PASS:',result.stdout)
    def test_api_success_and_one_direction_are_insufficient(self):
        result,calls=self.runner(True)
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(len(calls),2)
        self.assertNotIn('LAB_SUITE=PASS:',result.stdout)
if __name__=='__main__':unittest.main()
