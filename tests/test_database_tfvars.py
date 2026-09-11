import copy
import io
import json
import tempfile
import unittest
from contextlib import redirect_stderr
from pathlib import Path

from scripts.database_tfvars import ConversionError, build_database_tfvars, main
from scripts.infra_contract import ContractError


PLATFORM_CONTRACT = {
    "schemaVersion": "1.0",
    "environment": "homologation",
    "producer": "platform",
    "sourceCommit": "0123456789abcdef0123456789abcdef01234567",
    "publishedAt": "2026-09-11T12:00:00Z",
    "outputs": {
        "awsRegion": "us-east-1",
        "vpcId": "vpc-0123456789abcdef0",
        "publicSubnetIds": ["subnet-00000000000000001", "subnet-00000000000000002"],
        "privateApplicationSubnetIds": [
            "subnet-00000000000000003",
            "subnet-00000000000000004",
        ],
        "databaseSubnetIds": ["subnet-00000000000000005", "subnet-00000000000000006"],
        "clusterName": "garageflow-homologation",
        "clusterSecurityGroupId": "sg-0123456789abcdef0",
        "ecrRepositoryUrl": (
            "123456789012.dkr.ecr.us-east-1.amazonaws.com/garageflow-homologation"
        ),
        "apiGatewayId": "abcdefghij",
        "apiGatewayExecutionArn": (
            "arn:aws:execute-api:us-east-1:123456789012:abcdefghij"
        ),
        "jwtSecretArn": (
            "arn:aws:secretsmanager:us-east-1:123456789012:secret:"
            "garageflow/homologation/jwt-abc123"
        ),
        "internalAuthSecretArn": (
            "arn:aws:secretsmanager:us-east-1:123456789012:secret:"
            "garageflow/homologation/internal-auth-abc123"
        ),
        "bootstrapSecretArn": (
            "arn:aws:secretsmanager:us-east-1:123456789012:secret:"
            "garageflow/homologation/bootstrap-abc123"
        ),
        "webhookSecretArn": (
            "arn:aws:secretsmanager:us-east-1:123456789012:secret:"
            "garageflow/homologation/webhook-abc123"
        ),
        "snsTopicArn": "arn:aws:sns:us-east-1:123456789012:garageflow-homologation",
    },
    "consumerMetadata": {"trace": "permitted-additive-field"},
}


class BuildDatabaseTfvarsTests(unittest.TestCase):
    def test_builds_typed_tfvars_from_validated_complete_platform_contract(self):
        result = build_database_tfvars(
            PLATFORM_CONTRACT,
            environment="homologation",
            aws_region="us-east-1",
            owner="garageflow-team",
            expires_on="2026-09-30",
            allow_database_destroy=False,
        )

        self.assertEqual(PLATFORM_CONTRACT, result["platform_contract"])
        self.assertEqual("homologation", result["environment"])
        self.assertEqual("us-east-1", result["aws_region"])
        self.assertEqual("garageflow-team", result["owner"])
        self.assertEqual("2026-09-30", result["expires_on"])
        self.assertIs(False, result["allow_database_destroy"])
        self.assertNotIn("final_snapshot_identifier", result)

    def test_rejects_contract_environment_mismatch(self):
        mismatched = copy.deepcopy(PLATFORM_CONTRACT)
        mismatched["environment"] = "production"

        with self.assertRaises(ContractError):
            build_database_tfvars(
                mismatched,
                environment="homologation",
                aws_region="us-east-1",
                owner="garageflow-team",
                expires_on="2026-09-30",
            )

    def test_rejects_contract_region_mismatch_without_disclosing_value(self):
        mismatched = copy.deepcopy(PLATFORM_CONTRACT)
        mismatched["outputs"]["awsRegion"] = "eu-west-1"
        for field in (
            "ecrRepositoryUrl",
            "apiGatewayExecutionArn",
            "jwtSecretArn",
            "internalAuthSecretArn",
            "bootstrapSecretArn",
            "webhookSecretArn",
            "snsTopicArn",
        ):
            mismatched["outputs"][field] = mismatched["outputs"][field].replace(
                "us-east-1",
                "eu-west-1",
            )

        with self.assertRaises(ConversionError) as raised:
            build_database_tfvars(
                mismatched,
                environment="homologation",
                aws_region="us-east-1",
                owner="garageflow-team",
                expires_on="2026-09-30",
            )

        self.assertNotIn("eu-west-1", str(raised.exception))

    def test_cli_writes_json_tfvars_and_fails_closed_for_invalid_contract(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = Path(temporary_directory)
            contract_path = temporary_path / "platform.json"
            tfvars_path = temporary_path / "database.tfvars.json"
            contract_path.write_text(json.dumps(PLATFORM_CONTRACT), encoding="utf-8")

            result = main(
                [
                    "--input",
                    str(contract_path),
                    "--output",
                    str(tfvars_path),
                    "--environment",
                    "homologation",
                    "--aws-region",
                    "us-east-1",
                    "--owner",
                    "garageflow-team",
                    "--expires-on",
                    "2026-09-30",
                    "--allow-database-destroy",
                    "false",
                    "--final-snapshot-identifier",
                    "garageflow-homologation-final-reviewed",
                ]
            )

            self.assertEqual(0, result)
            document = json.loads(tfvars_path.read_text(encoding="utf-8"))
            self.assertEqual(
                "garageflow-homologation-final-reviewed",
                document["final_snapshot_identifier"],
            )

            invalid = copy.deepcopy(PLATFORM_CONTRACT)
            invalid["outputs"]["databasePassword"] = "must-never-be-printed"
            contract_path.write_text(json.dumps(invalid), encoding="utf-8")
            tfvars_path.unlink()
            stderr = io.StringIO()
            with redirect_stderr(stderr):
                result = main(
                    [
                        "--input",
                        str(contract_path),
                        "--output",
                        str(tfvars_path),
                        "--environment",
                        "homologation",
                        "--aws-region",
                        "us-east-1",
                        "--owner",
                        "garageflow-team",
                        "--expires-on",
                        "2026-09-30",
                    ]
                )

            self.assertEqual(2, result)
            self.assertFalse(tfvars_path.exists())
            self.assertNotIn("must-never-be-printed", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
