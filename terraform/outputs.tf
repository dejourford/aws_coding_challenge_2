output "region" {
  value = var.region
}

output "cluster_name" {
  value = aws_eks_cluster.example.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.example.endpoint
}

output "ecr_repository_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "jenkins_url" {
  value = "http://${aws_eip.jenkins.public_ip}:8080"
}
