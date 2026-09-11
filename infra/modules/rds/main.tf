locals {
  database_name = "garageflow"
  database_user = "garageflowadmin"
  database_port = 5432
  secret_payload = {
    database = local.database_name
    password = random_password.database.result
    username = local.database_user
  }
}

resource "random_password" "database" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "database" {
  name                    = var.database_secret_name
  description             = "GarageFlow database credentials managed by the database infrastructure root"
  recovery_window_in_days = var.secret_recovery_window_in_days

  tags = merge(var.tags, {
    Name = var.database_secret_name
  })
}

resource "aws_secretsmanager_secret_version" "database" {
  secret_id     = aws_secretsmanager_secret.database.id
  secret_string = jsonencode(local.secret_payload)
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.identifier}-subnets"
  subnet_ids = var.database_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.identifier}-subnets"
  })
}

resource "aws_security_group" "database" {
  name        = "${var.identifier}-database"
  description = "Allow PostgreSQL access only from the GarageFlow EKS cluster"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.identifier}-database"
  })
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_eks" {
  security_group_id            = aws_security_group.database.id
  description                  = "PostgreSQL from the platform EKS cluster"
  from_port                    = local.database_port
  to_port                      = local.database_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.cluster_security_group_id
  tags                         = var.tags
}

resource "aws_db_instance" "this" {
  identifier                   = var.identifier
  engine                       = "postgres"
  engine_version               = "17"
  instance_class               = "db.t3.micro"
  allocated_storage            = 20
  storage_type                 = "gp2"
  storage_encrypted            = true
  multi_az                     = false
  publicly_accessible          = false
  monitoring_interval          = 0
  performance_insights_enabled = false
  deletion_protection          = var.deletion_protection
  skip_final_snapshot          = false
  final_snapshot_identifier    = var.final_snapshot_identifier
  backup_retention_period      = 7
  copy_tags_to_snapshot        = true
  apply_immediately            = true

  db_name  = local.database_name
  username = local.database_user
  password = random_password.database.result
  port     = local.database_port

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.database.id]

  tags = merge(var.tags, {
    Name = var.identifier
  })
}
