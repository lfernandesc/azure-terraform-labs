# Application Gateway vs Front Door: regional failure, global failover and origin isolation

A regional reverse proxy cannot, by itself, give a public application a global entry point with automatic regional selection. This lab deploys **both services**, compares direct regional responses with a Front Door endpoint, breaks a regional health probe, observes failover and recovery, then removes the operator's temporary origin-access exception.

- [Portuguese article](https://lucas.fernandesc.workers.dev/blog/azure-frontdoor-application-gateway/)
- [English article](https://lucas.fernandesc.workers.dev/en/blog/azure-frontdoor-application-gateway/)
- [Full Portuguese lab guide](https://lucas.fernandesc.workers.dev/labs/azure-frontdoor-application-gateway/)
- [Full English lab guide](https://lucas.fernandesc.workers.dev/en/labs/azure-frontdoor-application-gateway/)

## Scope and explicit tradeoffs

```
HTTPS client -> Front Door Standard (no caching, priority 1/2)
                    | HTTP                    | HTTP
               App Gateway v2            App Gateway v2
               primary region            secondary region
                    | HTTP/private IP         | HTTP/private IP
                 private VM                private VM
```

Two VNets, two public Standard_v2 gateways (capacity 1), two small Linux VMs without public IPs, Front Door Standard, Log Analytics and diagnostic settings are created in one disposable RG. Each VM runs a small Python service from cloud-init/systemd. Ubuntu includes Python; bootstrap does not install packages. No VNet peering is needed because each gateway targets its own VNet. The SSH public key is an Azure VM provisioning requirement; the lab opens no SSH port.

**This is an HTTP routing/failover experiment, not a production security template.** TLS terminates at Front Door; the Front Door-to-gateway and gateway-to-VM hops are HTTP. Never send real data, cookies, tokens or credentials. `certificate_name_check_enabled=true` does not encrypt an HTTP hop. Production needs HTTPS listeners, trusted origin certificates/SNI and backend TLS, or an intentionally designed alternative. No WAF, Private Link, autoscaling, database replication, sessions or application authentication is deployed. Single VM/instance per region is a teaching simplification, not regional HA. Ubuntu `latest` is resolved at deployment: record/pin the resolved image version for repeatability.

The sample application checks `X-Azure-FDID` on `/checkout`; `/health` is minimal and accepts GET/HEAD without that header. Header filtering is **not user authentication** and the identifier is not a secret. The gateway NSGs allow `AzureFrontDoor.Backend`, required platform traffic and initially one operator `/32`. Removing that exception is the final phase. The header alone is spoofable; the service tag alone includes other customers' Front Door profiles. Use the controls together. Production commonly enforces the profile check at the gateway/WAF, not just in sample application code.

## Cost and prerequisites

This lab is deliberately more expensive than a single-VM exercise: **two Application Gateways**, Front Door base/usage charges, public IPs, two VMs/disks and logs are billable. Review the [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/) with your regions and subscription before applying. No free-tier or fixed-price claim. Deploy for a short session and destroy immediately after evidence collection; build/provisioning and propagation can take tens of minutes.

Use Terraform >=1.7, Azure CLI, Python >=3.10, Bash, an existing RSA/Ed25519 **public** key and a subscription permitted to create these resources. Check Network/Compute/CDN/OperationalInsights quotas, regional SKU availability, organisational policies and permissions. Use a stable public IPv4 (direct tests are IPv4-only). If a VPN/proxy/NAT changes your source, the `/32` exception and isolation conclusions are invalid. The probe intentionally bypasses HTTP proxy environment variables.

## 1. Baseline

```bash
az login
az account set --subscription YOUR-SUBSCRIPTION-ID
# Register these providers if your subscription has not already registered them.
az provider register --namespace Microsoft.Network --wait
az provider register --namespace Microsoft.Compute --wait
az provider register --namespace Microsoft.Cdn --wait
az provider register --namespace Microsoft.OperationalInsights --wait
az provider register --namespace Microsoft.Insights --wait
cp terraform.tfvars.example terraform.tfvars
# Edit subscription_id, your actual public IPv4/32 and your SSH PUBLIC key.
terraform init
terraform fmt -check
terraform validate
terraform plan -out=baseline.tfplan
terraform show baseline.tfplan
terraform apply baseline.tfplan
bash scripts/run-probe.sh baseline
```

Do not use the documentation IP from the example or a broad CIDR. Both `break_primary_probe=false` and `allow_direct_tests=true` must be persisted in tfvars. Verify that the plan provisions only this isolated RG. Baseline requires five consecutive correct observations per test: direct primary/secondary return 200 with the supplied profile header; each rejects a missing header with the application's 403; Front Door returns the primary deployment without the client supplying FDID. It is Front Door that sets that header on the origin request.

Read `STAGE_RESULT: PASS` in the JSON output (rendered as `"STAGE_RESULT": "PASS"`). Each nested probe must pass. The request body must identify this deployment, expected region, service and fresh request ID. An arbitrary 200 or cached response cannot pass.

Check backend health if initial convergence fails:

```bash
RG=$(terraform output -raw resource_group)
GW=$(terraform output -json gateway_names | python3 -c 'import json,sys;print(json.load(sys.stdin)["primary"])')
az network application-gateway show-backend-health --resource-group "$RG" --name "$GW"
```

A failed cloud-init/systemd process, NSG, subnet, wrong port or missing permissions can also break readiness. Diagnose rather than weakening network rules. VM boot diagnostics can help; Azure Run Command is an optional control-plane troubleshooting method and depends on a healthy VM agent. Private backend subnets have default outbound disabled and no NAT; arbitrary package installation/Internet updates are outside this exercise.

## 2. Controlled regional failure

Persist `break_primary_probe=true` and keep the direct-test exception enabled:

```bash
terraform plan -out=broken.tfplan
terraform show broken.tfplan
terraform apply broken.tfplan
bash scripts/run-probe.sh broken
```

The intended change is **only** the primary gateway's backend probe path `/health` -> `/missing`. Its private VM still exists and returns 404 on that missing path. After gateway health detection, direct primary requests return 502; direct secondary requests still pass; Front Door eventually returns secondary. Inspect the backend-health reason and recorded sample timestamps. The script waits up to 900 seconds **per probe**, requires five consecutive matches and may observe transient errors. An observation timeout means missing evidence, not proof that failover is impossible.

This is a probe misconfiguration, not a simulated full Azure region outage. Detection has two stages (gateway backend health and Front Door origin health), distributed probe windows and propagation. Do not promise a fixed RTO or infer global convergence from one client. Neither gateway autoscaling nor DNS TTL changes repair a wrong probe path.

## 3. Recovery

Persist `break_primary_probe=false`; keep all other variables unchanged:

```bash
terraform plan -out=recovered.tfplan
terraform show recovered.tfplan
terraform apply recovered.tfplan
bash scripts/run-probe.sh recovered
```

Require healthy direct responses from both regions and Front Door returning primary again, after health convergence. Priority 1 wins only while healthy. No cache block or session affinity is configured. Application JSON uses `Cache-Control: no-store`; every probe carries a unique nonce and request ID.

## 4. Origin isolation

Only after the recovered phase passes, persist `allow_direct_tests=false` (and `break_primary_probe=false`):

```bash
terraform plan -out=isolated.tfplan
terraform show isolated.tfplan
terraform apply isolated.tfplan
bash scripts/run-probe.sh isolated
```

The plan must remove `TemporaryOperatorTest` from **both** gateway NSGs, retaining Front Door and platform allowances. The script opens fresh connections and requires IP-level timeouts from the same operator, while the edge works before and after. DNS resolution failures, HTTP 403s and generic connection errors do not pass the isolation check. Inspect actual NSG configuration as a second piece of evidence:

```bash
az network nsg rule list --resource-group "$RG" --nsg-name nsg-appgateway-primary --output table
az network nsg rule list --resource-group "$RG" --nsg-name nsg-appgateway-secondary --output table
```

The absence of the operator exception plus working Front Door and direct timeouts is evidence of this restriction from this client. A timeout alone does not prove a secure origin or universal isolation. Keep the FDID application check. The FDID is deliberately supplied in the denied-network test to demonstrate that knowing it is insufficient when the network blocks you.

## Evidence and troubleshooting

Use `runbooks/evidence.md`. Gateway diagnostics use resource-specific `AGWAccessLogs`; Front Door diagnostics use `AzureDiagnostics`. Run the supplied KQL queries in the workspace named by `workspace_id`. Ingestion is delayed. Search the nonce in request URIs and the UTC interval; inspect actual fields in `Details` rather than assuming the gateway and edge schemas match. Gateway backend-health status and Front Door origin health are separate signals. Application logs remain in the VM systemd journal; they are not automatically shipped to the workspace.

- Front Door 503/504: inspect origin connectivity, origin health, Host header and route; do not classify every error as regional failover.
- Gateway 502: inspect the backend-health reason, probe path, private IP/port and process.
- Direct 403 with `wrong_frontdoor`: network allowed the request but the application rejected its FDID.
- Direct connection timeout after hardening: corroborate with both NSG configuration and positive controls.
- A primary region still returned during a transition: inspect convergence; a single response is not a failed algorithm.
- All origins unhealthy: Front Door can route across unhealthy origins as documented. A second broken region removes the recovery target; do not interpret active/passive as guaranteed availability.

## Cleanup

```bash
terraform plan -destroy -out=destroy.tfplan
terraform show destroy.tfplan
terraform apply destroy.tfplan
terraform state list
```

Confirm the disposable RG is gone and that no gateways, Front Door profile, disks, IPs or workspace remain. Do not delete state before successful destruction. State, saved plans and tfvars are local and must not be committed. The code references no shared production resources.

## Validation and limits

```bash
terraform init -backend=false
terraform fmt -check
terraform validate
bash -n scripts/run-probe.sh
python3 -m unittest discover -s tests -v
```

Author validation: provider-schema validation and 13 offline tests, including real localhost HTTP, GET/HEAD readiness, FDID acceptance/rejection and negative identity/correlation/region cases. **No Azure deployment, real gateway/edge failover, NSG isolation or end-to-end cloud telemetry was executed during authorship.** Local tests do not model the Azure control or data planes. All cloud outcomes above are acceptance criteria to verify in your subscription.

References: [regional/global selection](https://learn.microsoft.com/azure/architecture/guide/technology-choices/load-balancing-overview), [origin security](https://learn.microsoft.com/azure/frontdoor/origin-security), [Front Door probes](https://learn.microsoft.com/azure/frontdoor/health-probes), [routing priorities](https://learn.microsoft.com/azure/frontdoor/routing-methods), [gateway NSGs](https://learn.microsoft.com/azure/application-gateway/configuration-infrastructure).
