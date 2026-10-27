# Azure Terraform Labs

Hands-on Azure infrastructure labs by [Lucas Fernandes](https://www.linkedin.com/in/lucasfernandesc/), Cloud Engineer / DevOps.

Each lab starts with an intentional failure, uses diagnostic evidence to isolate the cause, and applies a focused Terraform correction. Code, diagnostic scripts, dependency locks and offline tests are versioned together.

| Lab | Problem | Correction |
| --- | --- | --- |
| [Private Endpoint DNS](labs/azure-private-endpoint-dns/) | Private Blob endpoint exists, but the client resolves the public endpoint | Link the private DNS zone to the client VNet |
| [Hub-Spoke routing](labs/azure-hub-spoke-routing/) | Two spokes cannot communicate through non-transitive VNet peering | Add symmetric UDRs through a disposable Linux NVA |

## Start / Começar

```bash
git clone https://github.com/lfernandesc/azure-terraform-labs.git
cd azure-terraform-labs/labs/azure-private-endpoint-dns
```

Read the selected lab README before deploying. Requirements include Terraform >=1.7, Azure CLI, Bash, Python 3 and an Azure subscription with the necessary permissions and quotas. Configure your own `terraform.tfvars` from the example; never commit credentials, state or plans.

Os guias completos, em português e inglês, estão no blog. Cada pasta inclui as instruções de execução, diagnóstico, validação e destruição. Para o segundo lab, entre em `labs/azure-hub-spoke-routing`.

## Verification and costs

Offline tests check diagnostic and runner behaviour; Terraform validation checks configuration against the provider schema. **No live Azure deployment was executed during authorship.** Expected cloud results in the guides are illustrative.

These labs create billable resources. Review the planned resources and region prices, then destroy the lab when finished. The single Linux NVA is educational and is not a production HA firewall.

## Contributing

Use a branch or fork and open a pull request. See [CONTRIBUTING.md](CONTRIBUTING.md). Lucas is the code owner for every path. Repository protection must also be enabled in GitHub; the CODEOWNERS file alone does not enforce approval.
