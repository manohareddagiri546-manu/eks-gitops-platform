locals { name = "${var.project_name}-${var.environment}" }

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  name = local.name
  cidr = "10.40.0.0/16"
  azs = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  private_subnets = ["10.40.0.0/20", "10.40.16.0/20", "10.40.32.0/20"]
  public_subnets  = ["10.40.128.0/24", "10.40.129.0/24", "10.40.130.0/24"]
  enable_nat_gateway = true
  single_nat_gateway = var.environment != "prod"
  enable_dns_hostnames = true
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }
  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
  tags = { Project = var.project_name, Environment = var.environment, ManagedBy = "Terraform" }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"
  cluster_name = local.name
  cluster_version = var.kubernetes_version
  cluster_endpoint_public_access = true
  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"] # Replace with trusted CIDRs before production.
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cluster_encryption_config = { resources = ["secrets"] }
  enable_cluster_creator_admin_permissions = true
  vpc_id = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  cluster_addons = {
    coredns = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni = { most_recent = true, before_compute = true }
    eks-pod-identity-agent = { most_recent = true }
  }
  eks_managed_node_groups = {
    general = {
      instance_types = var.node_instance_types
      min_size = 2
      max_size = 6
      desired_size = 2
      capacity_type = "ON_DEMAND"
    }
  }
  tags = { Project = var.project_name, Environment = var.environment, ManagedBy = "Terraform" }
}

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
  tags            = { Project = var.project_name, Environment = var.environment }
}

resource "aws_ecr_repository" "app" {
  name                 = "${local.name}-app"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
  tags = { Project = var.project_name, Environment = var.environment }
}

resource "aws_iam_role" "github_actions" {
  name = "${local.name}-github-actions"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike   = { "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:*" }
      }
    }]
  })
  tags = { Project = var.project_name, Environment = var.environment }
}

resource "aws_iam_role_policy" "github_ecr" {
  name = "ecr-publish"
  role = aws_iam_role.github_actions.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      {
        Effect = "Allow"
        Action = ["ecr:BatchCheckLayerAvailability", "ecr:CompleteLayerUpload", "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart"]
        Resource = aws_ecr_repository.app.arn
      }
    ]
  })
}
