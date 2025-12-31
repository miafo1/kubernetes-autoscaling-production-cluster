# outputs.tf

output "alb_dns_name" {
  description = "The DNS name of the load balancer"
  value       = aws_lb.main.dns_name
}

output "control_plane_ip" {
  description = "Public IP of the Control Plane (for debugging/kubectl setup)"
  value       = aws_instance.k3s_server.public_ip
}

output "control_plane_id" {
  description = "Instance ID of the Control Plane (for SSM access)"
  value       = aws_instance.k3s_server.id
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "ecr_repository_url" {
  description = "ECR Repository URL"
  value       = aws_ecr_repository.app_repo.repository_url
}
