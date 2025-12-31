# iam.tf
# IAM Roles and Policies for K3s Nodes

# --- Managed Policies ---
data "aws_iam_policy" "ssm_core" {
  arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy" "ecr_readonly" {
  arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# --- Service Trust Policy (Assume Role) ---
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# -----------------------------------------------------------------------------
# 1. K3s Server (Control Plane) Role
# -----------------------------------------------------------------------------
resource "aws_iam_role" "k3s_server" {
  name               = "${var.cluster_name}-server-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "server_ssm" {
  role       = aws_iam_role.k3s_server.name
  policy_arn = data.aws_iam_policy.ssm_core.arn
}

# Policy to simpler SSM Parameter Store access (Write Token)
resource "aws_iam_policy" "ssm_write_token" {
  name        = "${var.cluster_name}-ssm-write"
  description = "Allow writing K3s token to SSM"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${var.cluster_name}/k3s-token"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "server_ssm_write" {
  role       = aws_iam_role.k3s_server.name
  policy_arn = aws_iam_policy.ssm_write_token.arn
}

resource "aws_iam_instance_profile" "k3s_server" {
  name = "${var.cluster_name}-server-profile"
  role = aws_iam_role.k3s_server.name
}

# -----------------------------------------------------------------------------
# 2. K3s Agent (Worker) Role
# -----------------------------------------------------------------------------
resource "aws_iam_role" "k3s_agent" {
  name               = "${var.cluster_name}-agent-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "agent_ssm" {
  role       = aws_iam_role.k3s_agent.name
  policy_arn = data.aws_iam_policy.ssm_core.arn
}

resource "aws_iam_role_policy_attachment" "agent_ecr" {
  role       = aws_iam_role.k3s_agent.name
  policy_arn = data.aws_iam_policy.ecr_readonly.arn
}

# Policy to Read Token
resource "aws_iam_policy" "ssm_read_token" {
  name        = "${var.cluster_name}-ssm-read"
  description = "Allow reading K3s token from SSM"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${var.cluster_name}/k3s-token"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "agent_ssm_read" {
  role       = aws_iam_role.k3s_agent.name
  policy_arn = aws_iam_policy.ssm_read_token.arn
}

# Policy for Cluster Autoscaler (if running on agents)
resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "${var.cluster_name}-ca-policy"
  description = "Permissions for Cluster Autoscaler"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeTags",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "ec2:DescribeLaunchTemplateVersions"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "agent_ca" {
  role       = aws_iam_role.k3s_agent.name
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
}

resource "aws_iam_instance_profile" "k3s_agent" {
  name = "${var.cluster_name}-agent-profile"
  role = aws_iam_role.k3s_agent.name
}
