terraform {
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "~> 4.0"
        }
    }
}

provider "aws" {
    region = "us-east-1"
    shared_credentials_files = ["./credentials"]
}

locals {
    image = "ghcr.io/csse6400/taskoverflow_database:latest"
    database_username = "administrator"
    database_password = "foobarbaz"
}

resource "aws_db_instance" "taskoverflow_database" {
    allocated_storage = 20
    max_allocated_storage = 1000
    engine = "postgres"
    engine_version = "14"
    instance_class = "db.t4g.micro"
    db_name = "todo"
    username = local.database_username
    password = local.database_password
    parameter_group_name = "default.postgres14"
    skip_final_snapshot = true
    vpc_security_group_ids = [aws_security_group.taskoverflow_database.id]
    publicly_accessible = true

    tags = {
        Name = "taskoverflow_database"
    }
}

resource "aws_security_group" "taskoverflow_database" {
    name = "taskoverflow_database"
    description = "Allow inbound Postgresql traffic"

    ingress {
        from_port = 5432
        to_port = 5432
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
        ipv6_cidr_blocks = ["::/0"]
    }

    tags = {
        Name = "taskoverflow_database"
    }
}

data "aws_iam_role" "lab" {
    name = "LabRole"
}

data "aws_vpc" "default" {
    default = true
}

data "aws_subnets" "private" {
    filter {
        name = "vpc-id"
        values = [data.aws_vpc.default.id]
    }
}

resource "aws_ecs_cluster" "taskoverflow" {
    name = "taskoverflow"
}

resource "aws_ecs_task_definition" "taskoverflow" {
    family = "taskoverflow"
    network_mode = "awsvpc"
    requires_compatibilities = ["FARGATE"]
    cpu = 1024
    memory = 2048
    execution_role_arn = data.aws_iam_role.lab.arn
    container_definitions = <<DEFINITION
[
  {
    "image": "${local.image}",
    "cpu": 1024,
    "memory": 2048,
    "name": "todo",
    "networkMode": "awsvpc",
    "portMappings": [
      {
        "containerPort": 6400,
        "hostPort": 6400
      }
    ],
    "environment": [
      {
        "name": "SQLALCHEMY_DATABASE_URI",
        "value": "postgresql://${local.database_username}:${local.database_password}@${aws_db_instance.taskoverflow_database.address}:${aws_db_instance.taskoverflow_database.port}/${aws_db_instance.taskoverflow_database.db_name}"
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/taskoverflow/todo",
        "awslogs-region": "us-east-1",
        "awslogs-stream-prefix": "ecs",
        "awslogs-create-group": "true"
      }
    }
  }
]
DEFINITION
}

resource "aws_ecs_service" "taskoverflow" {
    name = "taskoverflow"
    cluster = aws_ecs_cluster.taskoverflow.id
    task_definition = aws_ecs_task_definition.taskoverflow.arn
    desired_count = 1
    launch_type = "FARGATE"

    network_configuration {
        subnets = data.aws_subnets.private.ids
        security_groups = [aws_security_group.taskoverflow.id]
        assign_public_ip = true
    }
}

resource "aws_security_group" "taskoverflow" {
    name = "taskoverflow"
    description = "TaskOverFlow Security Group"

    ingress {
        from_port = 6400
        to_port = 6400
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}
