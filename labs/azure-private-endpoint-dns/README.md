# Azure Private Endpoint DNS lab

A deliberate missing-VNet-link DNS failure, with private Blob Storage and a managed-identity client.

Guides / Guias:

- Português: https://lucasfernandes-dev.pages.dev/labs/azure-private-endpoint-dns/
- English: https://lucasfernandes-dev.pages.dev/en/labs/azure-private-endpoint-dns/

## Safety and scope

Creates billable Azure resources: VM/disk, NAT/public IP, Private Endpoint, DNS and Storage. Use a learning subscription, review costs and destroy the environment after use. Budget alerts do not delete resources. Requires permission to provision resources and assign Azure RBAC roles. No Azure deployment was executed while authoring this edition; expected HTTP outputs are illustrative.

## Quick start

Requires Bash, Azure CLI, Terraform >=1.7 and a real SSH public key. Provider lock: AzureRM 4.81.0, AzAPI 2.13.0, Random 3.9.1. The VM uses Ubuntu 22.04. Region and VM quota must be checked in your own subscription.

```bash
az login
az account set --subscription YOUR-SUBSCRIPTION-ID
cp terraform.tfvars.example terraform.tfvars
# Edit subscription_id and ssh_public_key; leave enable_private_dns_link=false.
terraform init
terraform fmt -check
terraform validate
terraform plan -out=broken.tfplan
terraform show broken.tfplan
terraform apply broken.tfplan
bash scripts/run-probe.sh broken
```

Do not proceed if the forced private HTTP request fails. Check identity/RBAC propagation, PE approval and connectivity. A generic 403 is not proof of a DNS-only problem.

Change `enable_private_dns_link = true` in `terraform.tfvars`, then:

```bash
terraform plan -out=fixed.tfplan
# Expect one added DNS VNet link, not a public access or RBAC change.
terraform show fixed.tfplan
terraform apply fixed.tfplan
bash scripts/run-probe.sh fixed
```

Storage is provisioned via the ARM-only AzAPI resource; no Blob data resource needs to be created by the laptop. AzureRM manages networking, VM and RBAC. The NAT's public IP is outbound-only, not attached to the VM; inbound access is denied. Run Command executes the guest probe without exposing SSH. State is local and may contain sensitive information; do not commit state, plans or .tfvars files. Keep `.terraform.lock.hcl` in version control.

## Offline probe tests

```bash
bash -n scripts/probe.sh scripts/run-probe.sh
python3 -m unittest discover -s tests -v
```

Six fixture-based tests verify diagnostic decisions and token non-disclosure. They do not execute requests to Azure.

## Teardown

```bash
terraform plan -destroy -out=destroy.tfplan
terraform show destroy.tfplan
terraform apply destroy.tfplan
terraform state list
```

Confirm deletion of the resource group in Azure before deleting local state. Stopping the VM does not remove the other billable resources.
