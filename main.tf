# Configure AWS provider
provider "aws" {
  region  = "eu-north-1" 
}

#################################################################
# VPC for networking
resource "aws_vpc" "fargate_vpc" {
  cidr_block = "10.0.0.0/16"  
}

# Public subnets for deploying resources with public access
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

# Route table to define routing for the public subnets
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.fargate_vpc.id 

  # Define a route to the internet via the internet gateway
  route {
    cidr_block = "0.0.0.0/0"  
    gateway_id = aws_internet_gateway.fargate_igw.id  
  }
}

# Associate the route table with public subnets
resource "aws_route_table_association" "public_subnet_1_association" {
  subnet_id      = aws_subnet.public_subnet_1.id  
  route_table_id = aws_route_table.public_route_table.id  
}

resource "aws_route_table_association" "public_subnet_2_association" {
  subnet_id      = aws_subnet.public_subnet_2.id  
  route_table_id = aws_route_table.public_route_table.id  
}

# Internet gateway to allow access to and from the internet
resource "aws_internet_gateway" "fargate_igw" {
  vpc_id = aws_vpc.fargate_vpc.id  
}

# Security group for ECS Fargate tasks
resource "aws_security_group" "fargate_sg" {
  vpc_id = aws_vpc.fargate_vpc.id  

  # Ingress rule to block all inbound traffic (deny by default)
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # Deny all traffic
    cidr_blocks = ["0.0.0.0/0"] 
  }

  # Egress rule to allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # Allow all protocols
    cidr_blocks = ["0.0.0.0/0"] 
  }
}

#################################################################
# ECS cluster for running Fargate tasks
resource "aws_ecs_cluster" "fargate_cluster" {
  name = "fargate-cluster-1"  
}

# IAM role for ECS task execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"  # IAM role for ECS task execution permissions
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"  # Allow ECS tasks to assume this role
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Attach required policies for ECS task execution role
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name  # Attach policy to the ECS task role
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"  # Predefined policy for ECS task execution
}

# CloudWatch Log Group for ECS task logs
resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/message-logger"  
  retention_in_days = 7  
}

# ECR repository for storing Docker images
resource "aws_ecr_repository" "message_logger_repo" {
  name = "message-logger"  
  image_scanning_configuration {
    scan_on_push = true  # Enable image scanning when the image is pushed to the repository
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "fargate_task" {
  family                   = "message-logger"  # ECS task family name
  network_mode             = "awsvpc"  # Use VPC networking mode
  requires_compatibilities = ["FARGATE"] 
  cpu                      = 256  
  memory                   = 512 
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn  # IAM role for task execution
  container_definitions    = jsonencode([
    {
      name      = "message-logger-container", 
      image     = aws_ecr_repository.message_logger_repo.repository_url, 
      essential = true,  # Mark container as essential for the task
      logConfiguration = {
        logDriver = "awslogs",  # Use CloudWatch logs for container logs
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_log_group.name,  # Specify log group
          "awslogs-region"        = "eu-north-1", 
          "awslogs-stream-prefix" = "ecs"  # Prefix for log stream
        }
      }
    }
  ])
}

#################################################################
# EventBridge rule to trigger ECS task
resource "aws_cloudwatch_event_rule" "eventbridge_rule" {
  name        = "eventbridge-rule"  
  description = "Rule to trigger ECS Fargate task"  

  event_pattern = jsonencode({
    "source": ["custom.my-application"],  
    "detail-type": ["myDetailType"]  
  })
}

# Target for EventBridge rule to trigger ECS task
resource "aws_cloudwatch_event_target" "ecs_target" {
  rule      = aws_cloudwatch_event_rule.eventbridge_rule.name  
  arn       = aws_ecs_cluster.fargate_cluster.arn  
  role_arn  = aws_iam_role.eventbridge_invoke_ecs_role.arn  # IAM role for EventBridge to invoke ECS

  ecs_target {
    task_definition_arn = aws_ecs_task_definition.fargate_task.arn  
    task_count          = 1  
    launch_type         = "FARGATE"  

    network_configuration {
      subnets          = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]  
      security_groups  = [aws_security_group.fargate_sg.id] 
      assign_public_ip = true  
    }
  }

  input = jsonencode({
    "source": "custom.my-application",  
    "detail-type": "myDetailType", 
    "detail": "$.detail"  # Pass the event detail as input to the ECS task
  })
}

#################################################################
# IAM Role for EventBridge to invoke ECS
resource "aws_iam_role" "eventbridge_invoke_ecs_role" {
  name = "eventbridgeInvokeEcsRole"  # IAM role for EventBridge to invoke ECS tasks
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "events.amazonaws.com"  # Allow EventBridge to assume this role
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Policy to allow EventBridge to invoke ECS tasks
resource "aws_iam_role_policy" "ecs_task_execution_from_eventbridge_policy" {
  role = aws_iam_role.eventbridge_invoke_ecs_role.name  # Attach policy to the EventBridge IAM role
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "ecs:RunTask",  # Allow running ECS tasks
        Resource = aws_ecs_task_definition.fargate_task.arn  # Specify the ECS task definition as the resource
      },
      {
        Effect = "Allow",
        Action = "iam:PassRole",  # Allow passing the ECS task execution role
        Resource = aws_iam_role.ecs_task_execution_role.arn  # Specify the ECS task execution role as the resource
      }
    ]
  })
}