# computing.tf
# EC2 Instances, Launch Templates, and Auto Scaling Group

# --- AMI ---
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --- Control Plane (Server) ---
resource "aws_instance" "k3s_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.small"  # Upgraded from t3.micro for better performance
  subnet_id     = aws_subnet.public_a.id # Control Plane in Public Subnet A
  
  iam_instance_profile   = aws_iam_instance_profile.k3s_server.name
  vpc_security_group_ids = [aws_security_group.k3s_node_sg.id]

  tags = {
    Name = "${var.cluster_name}-control-plane"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update && apt-get install -y unzip curl
              
              # Install AWS CLI
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              unzip awscliv2.zip
              ./aws/install

              # Install K3s Server
              # Disable Traefik if needed, but we keep it for simplicity.
              # We add --tls-san to allow access via Public IP if needed (improving debugging)
              PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
              PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
              
              curl -sfL https://get.k3s.io | sh -s - server \
                --tls-san $PUBLIC_IP \
                --node-external-ip $PUBLIC_IP

              # Wait for token
              while [ ! -f /var/lib/rancher/k3s/server/node-token ]; do
                echo "Waiting for K3s token..."
                sleep 2
              done

              TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)

              # Write to SSM
              aws ssm put-parameter \
                --name "/${var.cluster_name}/k3s-token" \
                --value "$TOKEN" \
                --type "SecureString" \
                --overwrite \
                --region ${var.aws_region}

              aws ssm put-parameter \
                --name "/${var.cluster_name}/server-ip" \
                --value "$PRIVATE_IP" \
                --type "String" \
                --overwrite \
                --region ${var.aws_region}
              
              echo "K3s Server initialized!"
              EOF
}

# --- Launch Template for Workers ---
resource "aws_launch_template" "k3s_agent" {
  name_prefix   = "${var.cluster_name}-agent-lt-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t3.small"  # Upgraded from t3.micro for better performance

  iam_instance_profile {
    name = aws_iam_instance_profile.k3s_agent.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.k3s_node_sg.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.cluster_name}-worker"
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
      "k8s.io/cluster-autoscaler/enabled" = "true"
      "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
    }
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt-get update && apt-get install -y unzip curl

              # Install AWS CLI
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              unzip awscliv2.zip
              ./aws/install

              # Retrieve Server IP and Token from SSM
              REGION="${var.aws_region}"
              
              # Wait for params
              while true; do
                SERVER_IP=$(aws ssm get-parameter --name "/${var.cluster_name}/server-ip" --query "Parameter.Value" --output text --region $REGION)
                TOKEN=$(aws ssm get-parameter --name "/${var.cluster_name}/k3s-token" --with-decryption --query "Parameter.Value" --output text --region $REGION)
                
                if [ "$SERVER_IP" != "None" ] && [ "$TOKEN" != "None" ]; then
                  break
                fi
                echo "Waiting for Server IP and Token..."
                sleep 5
              done

              PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

              # Install K3s Agent
              curl -sfL https://get.k3s.io | K3S_URL=https://$SERVER_IP:6443 K3S_TOKEN=$TOKEN sh -s - agent \
                --node-external-ip $PUBLIC_IP \
                --kubelet-arg="provider-id=aws:///$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)/$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"

              echo "K3s Agent initialized!"
              EOF
  )
}

# --- Auto Scaling Group ---
resource "aws_autoscaling_group" "k3s_workers" {
  name                = "${var.cluster_name}-asg"
  vpc_zone_identifier = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  min_size            = 1
  max_size            = 3
  desired_capacity    = 1

  launch_template {
    id      = aws_launch_template.k3s_agent.id
    version = "$Latest"
  }

  # Attach to ALB Target Group (defined in alb.tf, but referenced here)
  # We will output the ARN in alb.tf or use a variable. 
  # Actually, easier to define attachment in alb.tf or use target_group_arns here referencing alb.tf resource.
  # Terraform resolves dependencies.
  target_group_arns = [aws_lb_target_group.app_tg.arn]

  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-worker"
    propagate_at_launch = true
  }
}
