import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from tests.test_database_tfvars import PLATFORM_CONTRACT


ROOT = Path(__file__).resolve().parents[1]
DEPLOY_SCRIPT = ROOT / "scripts" / "deploy-database.sh"


class DatabaseDeploymentScriptTests(unittest.TestCase):
    def test_failed_conditional_revision_upload_does_not_publish_stable_contract(self):
        bash = shutil.which("bash")
        git_bash = Path("C:/Program Files/Git/bin/bash.exe")
        if os.name == "nt" and git_bash.exists():
            bash = str(git_bash)
        if bash is None:
            self.skipTest("Bash is required for the deployment script contract test")

        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = Path(temporary_directory)
            bin_path = temporary_path / "bin"
            runner_temp = temporary_path / "runner"
            bin_path.mkdir()
            runner_temp.mkdir()
            platform_fixture = temporary_path / "platform.json"
            platform_fixture.write_text(json.dumps(PLATFORM_CONTRACT), encoding="utf-8")
            aws_call_log = temporary_path / "aws-calls.log"

            aws_stub = bin_path / "aws"
            aws_stub.write_text(
                """#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\\n' "$*" >>"${AWS_CALL_LOG}"
if [[ "$1 $2" == 'sts get-caller-identity' ]]; then
  echo '123456789012'
elif [[ "$1 $2" == 'rds describe-orderable-db-instance-options' ]]; then
  echo '17.6'
elif [[ "$1 $2" == 's3 cp' && "$3" == s3://*/contracts/v1/homologation/platform.json ]]; then
  cp "${PLATFORM_FIXTURE}" "$4"
elif [[ "$1 $2" == 's3api put-object' ]]; then
  exit 55
fi
""",
                encoding="utf-8",
                newline="\n",
            )
            terraform_stub = bin_path / "terraform"
            terraform_stub.write_text(
                """#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "$*" == *'output -json deployment_outputs'* ]]; then
  printf '%s\\n' '{"databaseHost":"garageflow.example.us-east-1.rds.amazonaws.com","databasePort":5432,"databaseName":"garageflow","databaseSecretArn":"arn:aws:secretsmanager:us-east-1:123456789012:secret:garageflow/homologation/database-AbCdEf","databaseSecurityGroupId":"sg-1123456789abcdef0"}'
fi
""",
                encoding="utf-8",
                newline="\n",
            )
            aws_stub.chmod(0o755)
            terraform_stub.chmod(0o755)

            environment = os.environ.copy()
            environment.update(
                {
                    "AWS_ACCESS_KEY_ID": "test-access-key",
                    "AWS_SECRET_ACCESS_KEY": "test-secret-key",
                    "AWS_SESSION_TOKEN": "test-session-token",
                    "AWS_REGION": "us-east-1",
                    "AWS_DEFAULT_REGION": "us-east-1",
                    "EXPECTED_AWS_ACCOUNT_ID": "123456789012",
                    "TF_STATE_BUCKET": "garageflow-test-state",
                    "TF_VAR_owner": "garageflow-team",
                    "TF_VAR_expires_on": "2026-09-30",
                    "TF_VAR_allow_database_destroy": "false",
                    "DEPLOY_ENVIRONMENT": "homologation",
                    "GITHUB_REF": "refs/heads/develop",
                    "GITHUB_SHA": "0123456789abcdef0123456789abcdef01234567",
                    "GITHUB_RUN_ID": "12345",
                    "GITHUB_RUN_ATTEMPT": "1",
                    "RUNNER_TEMP": runner_temp.as_posix(),
                    "AWS_CALL_LOG": aws_call_log.as_posix(),
                    "PLATFORM_FIXTURE": platform_fixture.as_posix(),
                    "PATH": f"{bin_path}{os.pathsep}{environment['PATH']}",
                }
            )

            result = subprocess.run(
                [bash, DEPLOY_SCRIPT.as_posix()],
                cwd=ROOT,
                env=environment,
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )

            calls = aws_call_log.read_text(encoding="utf-8")
            self.assertEqual(55, result.returncode, result.stderr)
            self.assertIn("s3api put-object", calls)
            self.assertIn("--if-none-match *", calls)
            self.assertNotIn("contracts/v1/homologation/database.json", calls)


if __name__ == "__main__":
    unittest.main()
