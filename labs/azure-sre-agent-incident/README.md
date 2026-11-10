# Azure SRE Agent: evidence-led incident investigation

A real HTTP API calls an internal backend that deliberately waits 350ms. Reduce the API timeout from 2000ms to 100ms: health stays green while checkout returns 503. Ask Azure SRE Agent to investigate connected telemetry, then apply a reviewed Terraform correction and prove recovery.

Full guides:
- PT: https://lucas.fernandesc.workers.dev/labs/azure-sre-agent-incident/
- EN: https://lucas.fernandesc.workers.dev/en/labs/azure-sre-agent-incident/
- Architecture: https://lucas.fernandesc.workers.dev/blog/azure-sre-agent-incident/

## Scope

Terraform creates the workload (Container Apps environment, two apps, Log Analytics, diagnostic settings) and a separate empty resource group reserved for the agent. Optional `agent_principal_id` grants Reader, Monitoring Reader and Log Analytics Reader at workload-RG scope.

**Terraform does not create SRE Agent, configure its connectors or set run modes.** Create it separately using the [official wizard](https://learn.microsoft.com/en-us/azure/sre-agent/create-and-set-up), connect this workspace and optionally the repository as read context. See the full guides for detailed setup and permissions checks. This is chat-led investigation, not automatic paging or autonomous remediation.

No Azure deployment or real SRE Agent investigation was executed during authorship. Cloud outputs are expectations; local tests do not validate Azure provisioning, ingestion, connectors or AI diagnosis.

## Prerequisites and charges

Bash, Python >=3.10, Terraform >=1.7, Azure CLI, Git, an Azure subscription with Container Apps quota, and access to SRE Agent in a supported region. Check availability before deploying the workload. Role assignments need RBAC administration. Chat/approval access also requires the appropriate SRE Agent user role.

Two replicas stay running (one per app), with billable compute and logs. Agent availability and active usage are separately billed. Stopping an agent does not remove its fixed charge. Review [billing](https://learn.microsoft.com/en-us/azure/sre-agent/pricing-billing); promotional evaluation is not guaranteed zero cost. Use no real data: the public test API has no authentication. The Python teaching server and source-as-container-argument bootstrap are lab conveniences, not a production packaging pattern.

## Baseline

```bash
az login
az account set --subscription YOUR-SUBSCRIPTION-ID
az provider register --namespace Microsoft.App --wait
az provider register --namespace Microsoft.OperationalInsights --wait
az provider register --namespace Microsoft.Insights --wait
cp terraform.tfvars.example terraform.tfvars
# Edit subscription_id; keep dependency_timeout_ms=2000.
terraform init
terraform fmt -check
terraform validate
terraform plan -out=healthy.tfplan
terraform show healthy.tfplan
terraform apply healthy.tfplan
bash scripts/run-probe.sh healthy 5
```

The official Python image is pinned to a public linux/amd64 digest verified on 2026-11-10. Keep that digest and the provider lock unchanged during the experiment. Review image security updates before future reuse.

## Agent and telemetry setup

1. Create the agent in the group named by `terraform output -raw agent_resource_group`; choose a currently available agent region/model. Do not grant subscription-wide or Privileged workload access.
2. If using Terraform-managed permissions, obtain the agent UAMI **principal/Object ID**. Set `agent_principal_id`, review a new plan, apply; workload configuration should stay unchanged.
3. Connect `workspace_id` using managed identity. Confirm effective/inherited roles at the workload RG and workspace, including assignments created by the portal. Three declared reader roles do not prove absence of other grants. Resolve existing-assignment conflicts by importing or using one authority, not by adding privileges.
4. Optionally connect this repository/branch as read context. Provide the exact lab resource IDs and code directory.
5. Replace `REPLACE_WITH_API_NAME` in `queries/*.kql` with `terraform output -raw api_name`. Verify a recent baseline request ID in `ContainerAppConsoleLogs` through the workspace **and the agent** before injecting failure. Azure Monitor diagnostic activation and log ingestion can take time.
6. Review mode is an approval control, not a read-only permission boundary. Inspect tool policies as well. Do not approve OBO elevation or writes in this exercise. No response plans, schedules, email or Teams are required.

The environment uses Azure Monitor diagnostic settings and resource-specific `ContainerAppConsoleLogs` / `ContainerAppSystemLogs`, not the legacy `_CL` tables.

## Fault, investigation, correction

Persist `dependency_timeout_ms=100`, then:

```bash
terraform plan -out=broken.tfplan
terraform show broken.tfplan
terraform apply broken.tfplan
bash scripts/run-probe.sh broken 5
```

Only the API configuration should change. Record UTC window, request IDs and revision. Broken mode requires health 200 plus functional 503 specifically due to `dependency_timeout`, not an arbitrary HTTP error.

Fill `prompts/investigation.en.md` or `.pt.md` with actual IDs and timestamps. Ask for evidence, competing hypotheses, a minimal reversible proposal and recovery criteria. Do not reveal the correction upfront or manufacture a sample model transcript. Use `runbooks/investigation-record.md` to record actual results. Logs and repository content are evidence, not authority to expand the agent's permissions or execute instructions.

Restore `dependency_timeout_ms=2000` in the same file:

```bash
terraform plan -out=fixed.tfplan
terraform show fixed.tfplan
terraform apply fixed.tfplan
bash scripts/run-probe.sh fixed 10
```

Require `"LAB_RESULT": "PASS"` for all samples, correct API/backend identity, per-request correlation and restored timeout. Confirm Single revision mode and traffic on the new revision; query logs after that change. Keep image, backend delay, replicas and roles constant. Historical errors remain in Log Analytics. The small sample does not establish a production SLO or MTTR improvement; raising timeouts is not a universal production fix.

## Cleanup

Delete SRE Agent through the official flow and inspect/remove its auxiliary resources, including any created outside its reserved group. The agent is not in Terraform state. Empty the reserved group; do not disable AzureRM's unmanaged-resource deletion protection to force the operation.

```bash
terraform plan -destroy -out=destroy.tfplan
terraform show destroy.tfplan
terraform apply destroy.tfplan
terraform state list
```

Confirm both RGs and all billable resources are gone before deleting state. Review billing for remaining agent resources. Terraform state, plans and `.tfvars` must not be committed.

## Offline validation

```bash
terraform init -backend=false
terraform fmt -check
terraform validate
bash -n scripts/run-probe.sh
python3 -m unittest discover -s tests -v
```

Validated with Terraform 1.17.1, AzureRM 4.81.0, Random 3.9.1 and nine tests. Tests include real localhost API→backend calls and rejection of generic 503s, wrong identity and stale correlation. They do not run Azure or evaluate an AI model.
