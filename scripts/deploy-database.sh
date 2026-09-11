#!/usr/bin/env bash
set -Eeuo pipefail

required_variables=(
  AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY
  AWS_SESSION_TOKEN
  AWS_REGION
  EXPECTED_AWS_ACCOUNT_ID
  TF_STATE_BUCKET
  TF_VAR_owner
  TF_VAR_expires_on
  DEPLOY_ENVIRONMENT
  GITHUB_REF
  GITHUB_SHA
  GITHUB_RUN_ID
  GITHUB_RUN_ATTEMPT
  RUNNER_TEMP
)

missing_variables=()
for variable_name in "${required_variables[@]}"; do
  [[ -n "${!variable_name:-}" ]] || missing_variables+=("${variable_name}")
done

if (( ${#missing_variables[@]} > 0 )); then
  printf 'Database deployment refused: missing required variables: %s\n' "${missing_variables[*]}" >&2
  exit 1
fi

case "${GITHUB_REF}" in
  refs/heads/develop)
    expected_environment='homologation'
    ;;
  refs/heads/main)
    expected_environment='production'
    ;;
  *)
    echo 'Database deployment refused: only develop and main may deploy.' >&2
    exit 1
    ;;
esac

[[ "${DEPLOY_ENVIRONMENT}" == "${expected_environment}" ]] || {
  echo 'Database deployment refused: branch and environment do not match.' >&2
  exit 1
}
[[ "${AWS_REGION}" == 'us-east-1' ]] || {
  echo 'Database deployment refused: AWS region must be us-east-1.' >&2
  exit 1
}
[[ "${EXPECTED_AWS_ACCOUNT_ID}" =~ ^[0-9]{12}$ ]] || {
  echo 'Database deployment refused: expected AWS account ID is invalid.' >&2
  exit 1
}
[[ "${TF_STATE_BUCKET}" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]] || {
  echo 'Database deployment refused: state bucket name is invalid.' >&2
  exit 1
}
[[ "${GITHUB_SHA}" =~ ^[0-9a-f]{40}$ ]] || {
  echo 'Database deployment refused: source commit must be a full lowercase Git SHA.' >&2
  exit 1
}
[[ "${GITHUB_RUN_ID}" =~ ^[0-9]+$ && "${GITHUB_RUN_ATTEMPT}" =~ ^[0-9]+$ ]] || {
  echo 'Database deployment refused: workflow build identifiers are invalid.' >&2
  exit 1
}

allow_database_destroy="${TF_VAR_allow_database_destroy:-false}"
[[ "${allow_database_destroy}" == 'true' || "${allow_database_destroy}" == 'false' ]] || {
  echo 'Database deployment refused: allow_database_destroy must be true or false.' >&2
  exit 1
}

platform_contract_path="${RUNNER_TEMP}/garageflow-platform-${DEPLOY_ENVIRONMENT}.json"
generated_tfvars_path="${RUNNER_TEMP}/garageflow-database-${DEPLOY_ENVIRONMENT}.tfvars.json"
database_outputs_path="${RUNNER_TEMP}/garageflow-database-${DEPLOY_ENVIRONMENT}-outputs.json"
database_contract_path="${RUNNER_TEMP}/garageflow-database-${DEPLOY_ENVIRONMENT}-contract.json"
plan_path="${RUNNER_TEMP}/garageflow-database-${DEPLOY_ENVIRONMENT}-${GITHUB_SHA}.tfplan"

cleanup() {
  rm -f -- \
    "${platform_contract_path}" \
    "${generated_tfvars_path}" \
    "${database_outputs_path}" \
    "${database_contract_path}" \
    "${plan_path}"
}
trap cleanup EXIT

caller_account="$(aws sts get-caller-identity --query Account --output text --region "${AWS_REGION}")"
[[ "${caller_account}" == "${EXPECTED_AWS_ACCOUNT_ID}" ]] || {
  echo 'Database deployment refused: live AWS identity does not match the protected account metadata.' >&2
  exit 1
}

rds_pg17_versions="$(aws rds describe-orderable-db-instance-options \
  --region "${AWS_REGION}" \
  --engine postgres \
  --db-instance-class db.t3.micro \
  --query "OrderableDBInstanceOptions[?starts_with(EngineVersion, '17.')].EngineVersion" \
  --output text)"
[[ -n "${rds_pg17_versions}" ]] || {
  echo 'Database deployment refused: db.t3.micro with PostgreSQL 17 is unavailable in us-east-1.' >&2
  exit 1
}

platform_contract_key="contracts/v1/${DEPLOY_ENVIRONMENT}/platform.json"
if ! aws s3 cp \
  "s3://${TF_STATE_BUCKET}/${platform_contract_key}" \
  "${platform_contract_path}" \
  --region "${AWS_REGION}" \
  --only-show-errors; then
  echo "Database deployment blocked: validated platform metadata is missing at ${platform_contract_key}." >&2
  exit 1
fi

python scripts/infra_contract.py validate \
  --file "${platform_contract_path}" \
  --producer platform \
  --environment "${DEPLOY_ENVIRONMENT}"

tfvars_arguments=(
  --input "${platform_contract_path}"
  --output "${generated_tfvars_path}"
  --environment "${DEPLOY_ENVIRONMENT}"
  --aws-region "${AWS_REGION}"
  --owner "${TF_VAR_owner}"
  --expires-on "${TF_VAR_expires_on}"
  --allow-database-destroy "${allow_database_destroy}"
)
if [[ -n "${TF_VAR_final_snapshot_identifier:-}" ]]; then
  tfvars_arguments+=(--final-snapshot-identifier "${TF_VAR_final_snapshot_identifier}")
fi
python scripts/database_tfvars.py "${tfvars_arguments[@]}"

# Terraform receives only the validated JSON file, avoiding precedence or
# empty-string differences from the workflow's input environment.
unset TF_VAR_owner TF_VAR_expires_on TF_VAR_allow_database_destroy TF_VAR_final_snapshot_identifier

terraform -chdir=infra/database init \
  -reconfigure \
  -input=false \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="key=phase3/${DEPLOY_ENVIRONMENT}/database.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config='encrypt=true' \
  -backend-config='use_lockfile=true'

terraform -chdir=infra/database validate
terraform -chdir=infra/database plan \
  -input=false \
  -var-file="${generated_tfvars_path}" \
  -out="${plan_path}"
terraform -chdir=infra/database apply -input=false "${plan_path}"

database_identifier="garageflow-${DEPLOY_ENVIRONMENT}"
aws rds wait db-instance-available \
  --region "${AWS_REGION}" \
  --db-instance-identifier "${database_identifier}"

terraform -chdir=infra/database output -json deployment_outputs >"${database_outputs_path}"
python scripts/infra_contract.py publish \
  --input "${database_outputs_path}" \
  --output "${database_contract_path}" \
  --producer database \
  --environment "${DEPLOY_ENVIRONMENT}" \
  --source-commit "${GITHUB_SHA}"

revision_key="contracts/v1/${DEPLOY_ENVIRONMENT}/database/revisions/${GITHUB_SHA}/${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.json"
stable_key="contracts/v1/${DEPLOY_ENVIRONMENT}/database.json"
aws s3api put-object \
  --bucket "${TF_STATE_BUCKET}" \
  --key "${revision_key}" \
  --body "${database_contract_path}" \
  --content-type 'application/json' \
  --if-none-match '*' \
  --region "${AWS_REGION}" \
  >/dev/null
aws s3 cp "${database_contract_path}" "s3://${TF_STATE_BUCKET}/${stable_key}" \
  --region "${AWS_REGION}" \
  --only-show-errors

echo "Database metadata contract published for ${DEPLOY_ENVIRONMENT} at ${stable_key}."
