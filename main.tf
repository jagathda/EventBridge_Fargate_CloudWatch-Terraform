#Configure provider
provider "aws" {
  profile = "cli-user"
  region  = "eu-north-1"
}

#VPC for networking
resource "aws_vpc" "fargate_vpc" {
  cidr_block = "10.0.0.0/16"
}

#Public networks
resource "aws_subnet" "public_subnet_1" {
  vpc_id            = aws_vpc.fargate_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-north-1a"
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id            = aws_vpc.fargate_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-north-1b"
}

resource "aws_internet_gateway" "fargate_igw" {
  vpc_id = aws_vpc.fargate_vpc.id
}

resource "aws_security_group" "fargate_sg" {
  vpc_id = aws_vpc.fargate_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

################################################3

#Create ECS cluster
resource "aws_ecs_cluster" "fargate_cluster" {
  name = "fargate-cluster"
}

#ECS task execution role
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs_task_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

#ECS task policy attachment
resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

#ECS task definition
resource "aws_ecs_task_definition" "fargate_task" {
  family                   = "fargate-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([{
    name      = "message-logger-container"
    image     = "533266984673.dkr.ecr.eu-north-1.amazonaws.com/message-logger:latest"
    cpu       = 256
    memory    = 512
    essential = true
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/message-logger"
        "awslogs-region"        = "eu-north-1"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
}

#CloudWatch log group for ecs task
resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name = "/ecs/message-logger"
  retention_in_days = 14
}
