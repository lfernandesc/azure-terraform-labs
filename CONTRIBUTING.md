# Contributing

1. Fork the repository or create a feature branch; keep `main` for reviewed changes.
2. Explain the problem, the proposed correction and any changes to lab cost or permissions.
3. From each affected lab directory, run:

```bash
terraform init -backend=false
terraform fmt -check
terraform validate
bash -n scripts/*.sh
python3 -m unittest discover -s tests -v
```

4. Never run `scripts/setup-vm.sh` on your workstation: it is guest bootstrap code for disposable Azure VMs.
5. Open a PR against `main`. Describe which checks ran and whether a real Azure deployment was tested. Never report offline fixtures as an Azure test.
6. Wait for review by @lfernandesc. Changes after approval require another review.

Do not include credentials, private keys, `.tfvars`, Terraform state, plans or provider binaries. Keep the committed `.terraform.lock.hcl` files.

Português: contribuições entram por PR; Lucas revê as alterações. Inclua os resultados dos testes e atualize os guias PT/EN no repositório do blog quando o comportamento mudar.
