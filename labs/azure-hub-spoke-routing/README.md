# Azure Hub-Spoke routing lab

Classic VNet peering is not transitive. Reproduce an A-to-B failure, then add symmetric UDRs through a disposable Linux NVA.

Guides on the blog:

- PT: `/labs/azure-hub-spoke-routing/`
- EN: `/en/labs/azure-hub-spoke-routing/`

## Scope and costs

Three private Ubuntu 22.04 VMs, three disks, three NAT Gateways/public IPs, three VNets, four directional peerings and two route tables. NATs provide explicit independent management egress, not inter-spoke transit. No public VM NIC, inbound SSH or NVA SNAT is configured. Lab health checks use HTTP 8080 without sensitive data. Review region/quota/costs before use and destroy the environment afterwards.

This single-NVA Linux router is a teaching device, not a production firewall/HA architecture. No Azure deployment was executed during authorship; outputs in the guides are illustrative.

## Run

Requires Bash, Azure CLI, Terraform >=1.7 and a real SSH public key. The deployer needs resource provisioning, VM extension and Run Command permissions. Provider lock: AzureRM 4.81.0, Random 3.9.1.

```bash
az login
az account set --subscription YOUR-SUBSCRIPTION-ID
cp terraform.tfvars.example terraform.tfvars
# Edit subscription_id and ssh_public_key. Keep enable_spoke_transit=false.
terraform init
terraform fmt -check
terraform validate
terraform plan -out=broken.tfplan
terraform show broken.tfplan
terraform apply -parallelism=1 broken.tfplan
bash scripts/run-probe.sh broken
```

The guest setup script runs via Custom Script Extension as root only on these disposable VMs. NEVER execute `scripts/setup-vm.sh` on your workstation or an existing router: it changes forwarding/firewall settings. Initial apply is serialised to avoid concurrent changes on a shared peering VNet.

Persist `enable_spoke_transit=true` in `terraform.tfvars`:

```bash
terraform plan -out=fixed.tfplan
# Expect only two added spoke_transit routes.
terraform show fixed.tfplan
terraform apply fixed.tfplan
bash scripts/run-probe.sh fixed
```

Require `LAB_SUITE=PASS`, not merely an Azure CLI success or a single spoke's result. Fixed mode validates remote node identity and preserved client IP. Verify both NICs' effective routes separately. Keep state, plans and personal .tfvars out of Git; retain the dependency lock file.

## Offline checks

```bash
terraform init -backend=false
terraform fmt -check
terraform validate
bash -n scripts/setup-vm.sh scripts/probe.sh scripts/run-probe.sh
python3 -m unittest discover -s tests -v
```

Ten response-fixture tests check diagnostic and runner behaviour; they do not prove actual Azure networking. Guest setup's privileged system changes are not executed by the offline tests.

## Teardown

```bash
terraform plan -destroy -out=destroy.tfplan
terraform show destroy.tfplan
terraform apply -parallelism=1 destroy.tfplan
terraform state list
```

Confirm resource group deletion before deleting local state. Stopping VMs leaves other billable resources.
