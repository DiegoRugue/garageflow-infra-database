#!/usr/bin/env python3
"""Convert a validated platform manifest into database Terraform variables."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import date
from pathlib import Path

try:
    from .infra_contract import ContractError, load_contract, validate_contract
except ImportError:  # Direct execution: python scripts/database_tfvars.py
    from infra_contract import ContractError, load_contract, validate_contract


_ENVIRONMENTS = ("homologation", "production")
_REGION = "us-east-1"
_SNAPSHOT_PATTERN = re.compile(r"^[a-z][a-z0-9-]{0,253}[a-z0-9]$")


class ConversionError(ValueError):
    """Raised when validated contract metadata cannot produce safe tfvars."""


def _validate_text(value: object, field: str, maximum_length: int) -> str:
    if type(value) is not str or not value or value != value.strip():
        raise ConversionError(f"{field} must be a non-empty trimmed string")
    if len(value) > maximum_length or any(ord(character) < 32 or ord(character) == 127 for character in value):
        raise ConversionError(f"{field} has an invalid format")
    return value


def build_database_tfvars(
    platform_contract: dict,
    *,
    environment: str,
    aws_region: str,
    owner: str,
    expires_on: str,
    allow_database_destroy: bool = False,
    final_snapshot_identifier: str | None = None,
) -> dict:
    """Validate platform metadata and return a JSON-serializable tfvars object."""

    validated_contract = validate_contract(platform_contract, "platform", environment)
    if environment not in _ENVIRONMENTS:
        raise ConversionError("environment is unsupported")
    if aws_region != _REGION or validated_contract["outputs"]["awsRegion"] != aws_region:
        raise ConversionError("platform contract region does not match the deployment region")
    validated_owner = _validate_text(owner, "owner", 128)
    validated_expires_on = _validate_text(expires_on, "expires_on", 10)
    try:
        if date.fromisoformat(validated_expires_on).isoformat() != validated_expires_on:
            raise ValueError
    except ValueError as error:
        raise ConversionError("expires_on must use a valid YYYY-MM-DD date") from error
    if type(allow_database_destroy) is not bool:
        raise ConversionError("allow_database_destroy must be a boolean")

    tfvars = {
        "allow_database_destroy": allow_database_destroy,
        "aws_region": aws_region,
        "environment": environment,
        "expires_on": validated_expires_on,
        "owner": validated_owner,
        "platform_contract": validated_contract,
    }
    if final_snapshot_identifier is not None:
        snapshot_identifier = _validate_text(
            final_snapshot_identifier,
            "final_snapshot_identifier",
            255,
        )
        if _SNAPSHOT_PATTERN.fullmatch(snapshot_identifier) is None or "--" in snapshot_identifier:
            raise ConversionError("final_snapshot_identifier has an invalid format")
        tfvars["final_snapshot_identifier"] = snapshot_identifier
    return tfvars


def _write_tfvars(path: str, document: dict) -> None:
    try:
        with Path(path).open("w", encoding="utf-8", newline="\n") as stream:
            json.dump(document, stream, sort_keys=True, separators=(",", ":"))
            stream.write("\n")
    except OSError as error:
        raise ConversionError("database tfvars file could not be written") from error


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--environment", required=True, choices=_ENVIRONMENTS)
    parser.add_argument("--aws-region", required=True)
    parser.add_argument("--owner", required=True)
    parser.add_argument("--expires-on", required=True)
    parser.add_argument("--allow-database-destroy", choices=("false", "true"), default="false")
    parser.add_argument("--final-snapshot-identifier")
    return parser


def main(arguments: list[str] | None = None) -> int:
    options = _parser().parse_args(arguments)
    try:
        contract = load_contract(options.input, "platform", options.environment)
        tfvars = build_database_tfvars(
            contract,
            environment=options.environment,
            aws_region=options.aws_region,
            owner=options.owner,
            expires_on=options.expires_on,
            allow_database_destroy=options.allow_database_destroy == "true",
            final_snapshot_identifier=options.final_snapshot_identifier,
        )
        _write_tfvars(options.output, tfvars)
        return 0
    except (ContractError, ConversionError) as error:
        print(f"database-tfvars: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
