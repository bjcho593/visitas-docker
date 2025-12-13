provider "aws" {
  region = "us-east-1" # Cambia a tu región preferida
}

# --- DATOS DE LA RED EXISTENTE (DEFAULT VPC) ---
data "aws_vpc" "default" { default = true }
data "aws_subnets" "default" {
  filter { name = "vpc-id"; values = [data.aws_vpc.default.id] }
}

# --- SECURITY GROUPS ---
# 1. Para el Load Balancer (Abierto al mundo)
resource "aws_security_group" "lb_sg" {
  name   = "visitas-lb-sg"
  vpc_id = data.aws_vpc.default.id
  ingress { from_port = 80; to_port = 80; protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  egress  { from_port = 0;  to_port = 0;  protocol = "-1";  cidr_blocks = ["0.0.0.0/0"] }
}

# 2. Para las Instancias (Solo aceptan tráfico del LB)
resource "aws_security_group" "ec2_sg" {
  name   = "visitas-ec2-sg"
  vpc_id = data.aws_vpc.default.id
  ingress { from_port = 0; to_port = 65535; protocol = "tcp"; security_groups = [aws_security_group.lb_sg.id] }
  egress  { from_port = 0; to_port = 0;     protocol = "-1";  cidr_blocks = ["0.0.0.0/0"] }
}

# --- LOAD BALANCER (ALB) ---
resource "aws_lb" "app_lb" {
  name               = "visitas-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = data.aws_subnets.default.ids
}

# Target Group 1: FRONTEND
resource "aws_lb_target_group" "tg_front" {
  name     = "tg-frontend"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
  health_check { path = "/" }
}

# Target Group 2: BACKEND
resource "aws_lb_target_group" "tg_back" {
  name     = "tg-backend"
  port     = 8000
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
  health_check { path = "/" } # FastAPI responde en raiz
}

# Listener: Reglas de enrutamiento
resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = "80"
  protocol          = "HTTP"

  # Por defecto va al Frontend
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_front.arn
  }
}

# Regla: Si la ruta es /visitas* -> Manda al Backend
resource "aws_lb_listener_rule" "backend_rule" {
  listener_arn = aws_lb_listener.front_end.arn
  priority     = 100
  condition { path_pattern { values = ["/visitas*"] } }
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_back.arn
  }
}

# --- AWS 1: FRONTEND ASG ---
resource "aws_launch_template" "lt_front" {
  name_prefix   = "front-tpl-"
  image_id      = "ami-0c7217cdde317cfec" # Ubuntu 22.04 en us-east-1 (Revisar si usas otra region)
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  # USER DATA: Instala Docker y corre el Frontend
  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y docker.io
              systemctl start docker
              docker run -d -p 80:80 tu_usuario/visitas-web:v1
              EOF
  )
}

resource "aws_autoscaling_group" "asg_front" {
  desired_capacity    = 2
  max_size            = 3
  min_size            = 2
  vpc_zone_identifier = data.aws_subnets.default.ids
  target_group_arns   = [aws_lb_target_group.tg_front.arn]
  launch_template {
    id      = aws_launch_template.lt_front.id
    version = "$Latest"
  }
}

# --- AWS 2: BACKEND ASG ---
resource "aws_launch_template" "lt_back" {
  name_prefix   = "back-tpl-"
  image_id      = "ami-0c7217cdde317cfec"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  # USER DATA: Instala Docker, corre Redis y la API en la misma red local del host
  # Nota: En prod real, Redis debería ser un servicio Elasticache aparte.
  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y docker.io
              systemctl start docker
              docker network create app-net
              docker run -d --name redis-db --network app-net redis:alpine
              docker run -d -p 8000:8000 --network app-net tu_usuario/visitas-api:v1
              EOF
  )
}

resource "aws_autoscaling_group" "asg_back" {
  desired_capacity    = 2
  max_size            = 3
  min_size            = 2
  vpc_zone_identifier = data.aws_subnets.default.ids
  target_group_arns   = [aws_lb_target_group.tg_back.arn]
  launch_template {
    id      = aws_launch_template.lt_back.id
    version = "$Latest"
  }
}