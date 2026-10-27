# Azure Private Endpoint vs Service Endpoint lab

Compare a Private Endpoint DNS failure with a separate Storage account using a classic Service Endpoint, subnet firewall rules and the same VM managed identity.

Guides / Guias:

- Português: https://lucas.fernandesc.workers.dev/labs/azure-private-endpoint-dns/
- English: https://lucas.fernandesc.workers.dev/en/labs/azure-private-endpoint-dns/

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

## Compare Service Endpoint using a second account

After completing `fixed`, keep the DNS link set to `true`. This stage adds another Storage account and a read-only RBAC assignment for the same identity. It **does not** reopen the original private account. A separate account without a PE prevents private DNS for a shared account from masking the path being compared.

| Target and state | Expected VM DNS | Account public access | Subnet allow rule | Expected authenticated result |
| --- | --- | --- | --- | --- |
| PE account, DNS unlinked | Does not select the PE IP | `Disabled` | Not used on the private path | Normal `403`; forced private `200` |
| PE account, DNS linked | Private PE IP | `Disabled` | Not used on the private path | Normal `200` |
| SE account, allowed | Public service IPv4 | `Enabled` + default `Deny` | Client subnet only | `200` |
| SE account, denied | Same public DNS model | `Enabled` + default `Deny` | No allowed subnet | `403`, interpreted against prior success |

The Service Endpoint is enabled **on the source subnet** using `Microsoft.Storage`; the Storage account permits that subnet using `virtualNetworkRules`. Both accounts use the same region in this exercise. Do not add `Microsoft.Storage.Global` at the same time: these are alternative endpoint types. [VNet rule configuration](https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security-virtual-networks) requires both the subnet endpoint and the service-side rule.

### Enable comparison and establish allowed access

In the same `terraform.tfvars`:

```hcl
enable_private_dns_link             = true
enable_service_endpoint_comparison  = true
allow_service_endpoint_subnet       = true
```

```bash
terraform plan -out=service-allowed.tfplan
terraform show service-allowed.tfplan
terraform apply service-allowed.tfplan
bash scripts/run-probe.sh fixed
bash scripts/run-service-probe.sh allowed
```

Review additional resources and costs before applying: another Storage account, another `Storage Blob Data Reader` assignment and the client subnet's Service Endpoint. The original account must keep `publicNetworkAccess = "Disabled"`. The comparison account uses `Enabled`, `defaultAction = "Deny"`, `bypass = "None"`, no public IP exceptions, no anonymous Blob access and no Shared Key.

The new runner checks **live ARM properties**, not only Terraform outputs. It then lists containers from inside the VM, retrieves the NIC's effective routes and matches every guest-resolved address to active prefixes with next hop `VirtualNetworkServiceEndpoint`. HTTP `200` alone cannot pass through an unverified network path.

Illustrative summary, not a record of Azure execution:

```text
SERVICE_CONFIG=PASS: ...
SERVICE_DNS=<public-storage-ipv4>
SERVICE_HTTP=200
LAB_SERVICE_RESULT=PASS: ...
SERVICE_ROUTE=PASS: ...
SERVICE_COMPARISON=PASS: ...
```

Allow the new RBAC assignment to propagate if the first request returns `403`. Do not start the denial test until `SERVICE_COMPARISON=PASS` is established. Private or mixed DNS for the SE account is inconclusive; it should have no PE or DNS override. If route retrieval fails, check that the VM is running and the deployment identity can read effective routes.

### Remove only the subnet authorisation, then restore it

Change only:

```hcl
allow_service_endpoint_subnet = false
```

```bash
terraform plan -out=service-denied.tfplan
terraform show service-denied.tfplan
terraform apply service-denied.tfplan
bash scripts/run-service-probe.sh denied
bash scripts/run-probe.sh fixed
```

The plan should update the second account's ACL to remove the subnet rule, **without** removing the Service Endpoint, changing RBAC or unlinking PE DNS. The runner requires the ARM deny configuration, public DNS, the service route and HTTP `403`, but labels the outcome `OBSERVED_DENY`: an isolated error still cannot establish root cause. Compare it with prior `200` on the same account, identity and operation.

Persist `allow_service_endpoint_subnet = true` again, review a new plan, apply and rerun `bash scripts/run-service-probe.sh allowed`. The expected sequence is **200 → 403 → 200**, while the PE stays `fixed`. Investigate Storage errors and rule propagation if observations differ.

### Interpret evidence without equating public DNS with public internet

Inspect effective routes manually if needed:

```bash
az network nic show-effective-route-table \
  --resource-group "$(terraform output -raw resource_group)" \
  --name "$(terraform output -raw probe_nic_name)" --output json
```

Match the guest probe's address to `addressPrefix`, `state` and `nextHopType`. Finding an arbitrary Service Endpoint route is insufficient: it must cover the tested destination and be active. NAT remains in the lab for the VM agent; it is not the Storage Service Endpoint access mechanism. See the [routing documentation](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-udr-overview).

This comparison does not include a second source network, Storage data logs or Service Endpoint Policies. It therefore does not claim to prove blocking from every external source, central firewall inspection or complete exfiltration prevention. Those conclusions need additional observation points and tests.

## Offline checks

```bash
terraform init -backend=false
terraform fmt -check
terraform validate
bash -n scripts/*.sh
python3 -m unittest discover -s tests -v
```

26 fixture-based tests cover private/public/mixed DNS, authenticated responses, token non-disclosure, default-deny configuration and destination-matched effective routes. They do not execute requests to Azure.

## Teardown

```bash
terraform plan -destroy -out=destroy.tfplan
terraform show destroy.tfplan
terraform apply destroy.tfplan
terraform state list
```

Confirm deletion of the resource group in Azure before deleting local state. Stopping the VM does not remove the other billable resources.
