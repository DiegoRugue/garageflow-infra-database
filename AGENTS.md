# GarageFlow database infrastructure agent policy

## Scope

This repository owns only the GarageFlow PostgreSQL RDS instance, its subnet group, database security group, database credential secret, backup policy, and the database infrastructure deployment automation.

It does not own the VPC, subnets, EKS, application workloads, database tables, Entity Framework migrations, API Gateway, ingress, or application secrets.

## Repository boundaries

- Consume platform metadata only through the validated `contracts/v1/{environment}/platform.json` manifest.
- Do not read Terraform remote state from another root or refer to files in another checkout.
- Publish only the metadata fields in the versioned database contract. Never publish passwords, secret values, Terraform state, or plans.
- Keep each environment in `phase3/{environment}/database.tfstate`.
- Preserve PostgreSQL 17, `db.t3.micro`, 20 GiB encrypted storage, private access, seven-day backups, and explicit Single-AZ Academy sizing unless an approved design changes them.
- Production deletion protection and final-snapshot retention are the default. Any teardown must use an explicit, reviewed configuration change.

## Validation

Run the repository checks before committing:

```bash
python -m unittest discover -s scripts/tests -v
terraform fmt -check -recursive infra
terraform -chdir=infra/database init -backend=false -input=false
terraform -chdir=infra/database validate
terraform -chdir=infra/database test
bash -n scripts/deploy-database.sh
```

Terraform tests must use mock providers and must not require AWS credentials.

## Records and sensitive data

Keep plans, logs, reports, execution notes, and review records outside this and every other repository under `C:\projects\GarageFlow-study\sdd\2026-09-11-m1-infrastructure`. Never commit credentials, contract payloads downloaded from live environments, state, plans, or generated deployment tfvars.
