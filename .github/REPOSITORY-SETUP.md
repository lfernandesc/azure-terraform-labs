# Repository settings

These JSON files are configuration templates, not proof that protection is active. Apply both rulesets after pushing the initial main branch. Verify the live settings afterwards.

- `main-integrity`: all changes through a PR; no direct pushes, force pushes or branch deletion; no bypass.
- `main-owner-review`: one code-owner approval, stale approvals dismissed, conversations resolved. Only the repository admin role may bypass this review rule, and only through a PR. For this personal repository, keep admin access with Lucas alone. GitHub forbids approval of your own PR, so Lucas uses this exception to merge his own PRs. The separate integrity rule still blocks direct pushes.

With authenticated GitHub CLI and repository administration permission:

```bash
gh api --method POST repos/lfernandesc/azure-terraform-labs/rulesets --input .github/rulesets/main-integrity.json
gh api --method POST repos/lfernandesc/azure-terraform-labs/rulesets --input .github/rulesets/main-owner-review.json
gh api repos/lfernandesc/azure-terraform-labs/rulesets
```

Run creation once; update existing rulesets instead of creating duplicates. Check that GitHub recognises CODEOWNERS and that both rulesets are active and target main. Do not add other administrators without reviewing bypass privileges.
