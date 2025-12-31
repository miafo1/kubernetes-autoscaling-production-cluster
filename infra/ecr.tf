# ecr.tf
# Elastic Container Registry

resource "aws_ecr_repository" "app_repo" {
  name                 = "${var.cluster_name}-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.cluster_name}-app"
  }
}
