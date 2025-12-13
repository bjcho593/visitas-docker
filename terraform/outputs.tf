output "load_balancer_dns" {
  description = "DNS Publico del Load Balancer (Accede aqui)"
  value       = aws_lb.app_lb.dns_name
}

output "asg_frontend_name" {
  value = aws_autoscaling_group.asg_front.name
}

output "asg_backend_name" {
  value = aws_autoscaling_group.asg_back.name
}