# Tech Challenge 2

## Objective
Deploy a web application using **Docker**, orchestrate it with **AWS EKS**, and set up a **continuous deployment pipeline** using **Jenkins**.

## Tools Used
- **Node.js / Express** — simple web application serving "Hello, World!"
- **Docker** — containerizing the application and its dependencies
- **Amazon ECR** — storing and versioning Docker images
- **Terraform** — provisioning AWS infrastructure (EKS cluster, VPC, IAM roles)
- **AWS EKS** — orchestrating containers using Kubernetes with EC2 nodes
- **Helm** — packaging and deploying the application to Kubernetes
- **Jenkins** — CI/CD pipeline for building, pushing, and deploying the application
- **kubectl** — interacting with the EKS cluster from Jenkins
- **HPA (Horizontal Pod Autoscaler)** — scaling pods based on CPU/memory utilization
- **GitHub** — version control and webhook integration with Jenkins
- **GitHub Actions** — GitOps bonus CI pipeline (build + push to ECR)
- **ArgoCD** — GitOps bonus CD, syncing Helm charts to EKS automatically

## Procedure

### Phase 1 - Creating the Web Application

Step 1.1 - Create a directory named 'backend' and navigate into it

```
mkdir backend && cd backend
```

Step 1.2 - Initialize the Node project

```
npm init -y
```

Step 1.3 - Install Node.js, npm, and Express

```
sudo apt install nodejs npm -y
npm install express
```

Step 1.4 - Verify Installation

```
node -v
ls node_modules | grep express
```

Step 1.5 - Create a .gitignore file in the project root and add the following

```
node_modules
.env
npm-debug.log
.terraform/
.terraform.lock.hcl
*.tfstate
*.tfstate.backup
*.tfstate.lock.info
*.pem
```

Step 1.6 - Create index.js and write the web application

```javascript
const express = require('express')
const app = express()
const PORT = 3000

app.get('/', (req, res) => {
  res.send('Hello, World!')
})

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`)
})
```

Step 1.7 - Run the web application

```
node index.js
```

Step 1.8 - Navigate to localhost:3000 to verify "Hello, World!" is displayed

![Web Browser](./screenshots/web_browser.png)


### Phase 2 - Containerize the Application with Docker

Step 2.1 - Install Docker

```
sudo apt install docker.io -y
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER
```

Step 2.2 - Create a Dockerfile in the backend directory

```dockerfile
FROM node:18
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3000
CMD ["node", "index.js"]
```

Step 2.3 - Build the Docker image

```
docker build -t backend-app .
```

Step 2.4 - Run the container and verify "Hello, World!" is still displayed at localhost:3000

```
docker run -d --name backend -p 3000:3000 backend-app
```

![Docker Verified](./screenshots/docker_verify.png)


### Phase 3 - Provision Infrastructure with Terraform

Step 3.1 - Create a Terraform directory in the project root

```
mkdir terraform && cd terraform
touch provider.tf ecr.tf eks.tf variables.tf outputs.tf vpc.tf iam.tf
```

Step 3.2 - Add the provider block to provider.tf

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.49.0"
    }
  }
}

provider "aws" {
  region = var.region
}
```

Step 3.3 - Add the following to vpc.tf

```hcl
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
  }
}

resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = count.index == 0 ? "us-east-2a" : "us-east-2b"
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "${var.project_name}-public-subnet-${count.index + 1}"
    Environment                                 = var.environment
    "kubernetes.io/cluster/${var.project_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 2)
  availability_zone = count.index == 0 ? "us-east-2a" : "us-east-2b"

  tags = {
    Name                                        = "${var.project_name}-private-subnet-${count.index + 1}"
    Environment                                 = var.environment
    "kubernetes.io/cluster/${var.project_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "${var.project_name}-igw", Environment = var.environment }
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags = { Name = "${var.project_name}-nat-eip", Environment = var.environment }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags = { Name = "${var.project_name}-nat-gateway", Environment = var.environment }
  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route { cidr_block = "0.0.0.0/0"; gateway_id = aws_internet_gateway.main.id }
  tags = { Name = "${var.project_name}-public-rt", Environment = var.environment }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route { cidr_block = "0.0.0.0/0"; nat_gateway_id = aws_nat_gateway.main.id }
  tags = { Name = "${var.project_name}-private-rt", Environment = var.environment }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
```

Step 3.4 - Add the following to eks.tf

```hcl
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.example.name
  node_group_name = "${var.project_name}-node-group"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.private[*].id
  instance_types  = [var.instance_type]

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 4
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_AmazonEC2ContainerRegistryReadOnly,
  ]

  tags = { Name = "${var.project_name}-node-group", Environment = var.environment }
}

resource "aws_eks_cluster" "example" {
  name     = var.project_name
  role_arn = aws_iam_role.cluster.arn
  version  = "1.35"

  access_config { authentication_mode = "API" }

  vpc_config {
    subnet_ids = concat(aws_subnet.private[*].id, aws_subnet.public[*].id)
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy]

  tags = { Name = "${var.project_name}-eks-cluster", Environment = var.environment }
}
```

Step 3.5 - Add the following to iam.tf

```hcl
resource "aws_iam_role" "cluster" {
  name = "${var.project_name}-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = ["sts:AssumeRole", "sts:TagSession"], Effect = "Allow", Principal = { Service = "eks.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role" "node" {
  name = "${var.project_name}-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node.name
}
```

Step 3.6 - Add the following to ecr.tf

```hcl
resource "aws_ecr_repository" "backend" {
  name                 = "${var.project_name}-backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = true }
  tags = { Name = "${var.project_name}-backend-repo", Environment = var.environment }
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = { tagStatus = "tagged", tagPrefixList = ["v"], countType = "imageCountMoreThan", countNumber = 5 }
      action = { type = "expire" }
    }]
  })
}
```

Step 3.7 - Add the following to outputs.tf

```hcl
output "region" { value = var.region }
output "cluster_name" { value = aws_eks_cluster.example.name }
output "cluster_endpoint" { value = aws_eks_cluster.example.endpoint }
output "ecr_repository_url" { value = aws_ecr_repository.backend.repository_url }
```

Step 3.8 - Add the following to variables.tf

```hcl
variable "project_name" { type = string; default = "aws_coding_challenge_2" }
variable "environment"  { type = string; default = "dev" }
variable "region"       { type = string; default = "us-east-2" }
variable "vpc_cidr"     { type = string; default = "10.0.0.0/16" }
variable "instance_type"{ type = string; default = "t3.small" }
variable "key_name"     { type = string; default = "<your-key-pair-name>" }
```

Step 3.9 - Initialize Terraform

```
terraform init
```

![Terraform Init](./screenshots/init.png)

Step 3.10 - Apply the infrastructure

```
terraform apply
```

![Terraform Apply](./screenshots/apply.png)


### Phase 4 - Push Docker Image to ECR

Step 4.1 - Authenticate Docker to ECR

```
aws ecr get-login-password --region <your-region> | docker login --username AWS --password-stdin <your-account-id>.dkr.ecr.<your-region>.amazonaws.com
```

Step 4.2 - Tag your Docker image

```
docker tag backend-app:latest <your-account-id>.dkr.ecr.<your-region>.amazonaws.com/<your-ecr-repo-name>:latest
```

Step 4.3 - Push Docker image to ECR

```
docker push <your-account-id>.dkr.ecr.<your-region>.amazonaws.com/<your-ecr-repo-name>:latest
```


### Phase 5 - Deploy to EKS

Step 5.1 - Configure kubectl to connect to the EKS cluster

```
aws eks update-kubeconfig --region <your-region> --name <your-cluster-name>
```

Step 5.2 - Verify the nodes are ready

```
kubectl get nodes
```

Step 5.3 - Create Kubernetes manifest directory and files

```
mkdir k8s
touch k8s/deployment.yaml k8s/service.yaml k8s/hpa.yaml
```

deployment.yaml
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  labels:
    app: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
        - name: backend
          image: <your-account-id>.dkr.ecr.<your-region>.amazonaws.com/<your-ecr-repo-name>:latest
          ports:
            - containerPort: 3000
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi
```

service.yaml
```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend
spec:
  selector:
    app: backend
  ports:
    - protocol: TCP
      port: 80
      targetPort: 3000
  type: LoadBalancer
```

hpa.yaml
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: backend-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: backend
  minReplicas: 1
  maxReplicas: 3
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 50
```

Step 5.4 - Apply manifests to the cluster

```
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/hpa.yaml
```

Step 5.5 - Verify everything is running

```
kubectl get pods
kubectl get services
kubectl get hpa
```

Step 5.6 - Navigate to `http://<your-loadbalancer-external-ip>` to verify the application


### Phase 6 - Set up Jenkins CI/CD Pipeline

Step 6.1 - Create jenkins.tf in the terraform directory

```hcl
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter { name = "name"; values = ["al2023-ami-*-x86_64"] }
  filter { name = "virtualization-type"; values = ["hvm"] }
}

resource "aws_security_group" "jenkins" {
  name        = "${var.project_name}-jenkins-sg"
  description = "Security group for Jenkins server"
  vpc_id      = aws_vpc.main.id

  ingress { description = "SSH"; from_port = 22; to_port = 22; protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  ingress { description = "Jenkins Web UI"; from_port = 8080; to_port = 8080; protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  egress  { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }

  tags = { Name = "${var.project_name}-jenkins-sg", Environment = var.environment }
}

resource "aws_instance" "jenkins" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.jenkins.id]
  key_name               = var.key_name

  user_data = <<-EOF
    #!/bin/bash
    dnf install wget java-21-amazon-corretto docker git -y
    wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
    rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
    dnf install jenkins -y
    systemctl enable jenkins && systemctl start jenkins
    systemctl enable docker && systemctl start docker
    usermod -aG docker jenkins
    systemctl restart jenkins
  EOF

  root_block_device { volume_size = 30; volume_type = "gp3"; encrypted = true }
  tags = { Name = "${var.project_name}-jenkins", Environment = var.environment }
}

resource "aws_eip" "jenkins" {
  instance = aws_instance.jenkins.id
  domain   = "vpc"
  tags = { Name = "${var.project_name}-jenkins-eip", Environment = var.environment }
}
```

Step 6.2 - Add jenkins_url to outputs.tf

```hcl
output "jenkins_url" {
  value = "http://${aws_eip.jenkins.public_ip}:8080"
}
```

Step 6.3 - Run Terraform apply

```
terraform apply
```

Step 6.4 - Navigate to `http://<your-jenkins-ip>:8080`

Step 6.5 - SSH into the Jenkins EC2 to get the initial admin password

```
ssh -i ~/.ssh/<your-key-pair>.pem ec2-user@<your-jenkins-ip>
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Step 6.6 - Install plugins via Manage Jenkins → Plugins → Available Plugins
- Docker
- Amazon EC2
- Amazon Elastic Container Service (ECS) / Fargate
- Kubernetes
- Kubernetes CLI

Step 6.7 - Add credentials via Manage Jenkins → Credentials → System → Global → Add Credentials
- GitHub PAT (Kind: Username with password, ID: github_pat)
- AWS Credentials (Kind: AWS Credentials, ID: aws_keys)

Step 6.8 - Install AWS CLI on the Jenkins EC2

```
sudo dnf install awscli -y
```

Step 6.9 - Install kubectl on the Jenkins EC2

```
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/
kubectl version --client
```

Step 6.10 - Configure AWS credentials on the Jenkins EC2

```
aws configure
```

Step 6.11 - Configure kubectl to connect to the EKS cluster

```
aws eks update-kubeconfig --region <your-region> --name <your-cluster-name>
```

Step 6.12 - Install Helm on the Jenkins EC2

```
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

Step 6.13 - Create Helm chart structure in the project root

```
mkdir -p helm/backend/templates
touch helm/backend/Chart.yaml helm/backend/values.yaml
touch helm/backend/templates/deployment.yaml helm/backend/templates/service.yaml helm/backend/templates/hpa.yaml
```

Chart.yaml
```yaml
apiVersion: v2
name: backend
description: A Helm chart for the backend application
type: application
version: 0.1.0
appVersion: "1.0.0"
```

values.yaml
```yaml
image:
  repository: <your-account-id>.dkr.ecr.<your-region>.amazonaws.com/<your-ecr-repo-name>
  tag: latest
  pullPolicy: Always

service:
  type: LoadBalancer
  port: 80
  targetPort: 3000

replicaCount: 1

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi

hpa:
  minReplicas: 1
  maxReplicas: 3
  cpuUtilization: 50
  memoryUtilization: 50
```

templates/deployment.yaml
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}
  labels:
    app: {{ .Release.Name }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app: {{ .Release.Name }}
    spec:
      containers:
        - name: {{ .Release.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: {{ .Values.service.targetPort }}
          resources:
            requests:
              cpu: {{ .Values.resources.requests.cpu }}
              memory: {{ .Values.resources.requests.memory }}
            limits:
              cpu: {{ .Values.resources.limits.cpu }}
              memory: {{ .Values.resources.limits.memory }}
```

templates/service.yaml
```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}
spec:
  selector:
    app: {{ .Release.Name }}
  ports:
    - protocol: TCP
      port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort }}
  type: {{ .Values.service.type }}
```

templates/hpa.yaml
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ .Release.Name }}-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ .Release.Name }}
  minReplicas: {{ .Values.hpa.minReplicas }}
  maxReplicas: {{ .Values.hpa.maxReplicas }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ .Values.hpa.cpuUtilization }}
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: {{ .Values.hpa.memoryUtilization }}
```

Step 6.14 - Create a Jenkinsfile in the project root

```groovy
pipeline {
    agent any

    environment {
        AWS_REGION   = '<your-region>'
        ECR_REPO     = '<your-account-id>.dkr.ecr.<your-region>.amazonaws.com/<your-ecr-repo-name>'
        CLUSTER_NAME = '<your-cluster-name>'
        IMAGE_TAG    = "${BUILD_NUMBER}"
    }

    stages {
        stage('Checkout code') {
            steps { checkout scm }
        }

        stage('Build Docker image') {
            steps {
                script { sh 'docker build -t backend-app:${IMAGE_TAG} ./backend' }
            }
        }

        stage('Authenticate to ECR') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws_keys']]) {
                    script {
                        sh 'aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO'
                    }
                }
            }
        }

        stage('Tag and Push image to ECR') {
            steps {
                script {
                    sh '''
                        docker tag backend-app:${IMAGE_TAG} $ECR_REPO:${IMAGE_TAG}
                        docker tag backend-app:${IMAGE_TAG} $ECR_REPO:latest
                        docker push $ECR_REPO:${IMAGE_TAG}
                        docker push $ECR_REPO:latest
                    '''
                }
            }
        }

        stage('Deploy to EKS with Helm') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws_keys']]) {
                    script {
                        sh '''
                            aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME
                            helm upgrade --install backend ./helm/backend \
                                --set image.repository=$ECR_REPO \
                                --set image.tag=${IMAGE_TAG}
                        '''
                    }
                }
            }
        }
    }

    post {
        always { cleanWs() }
    }
}
```

Step 6.15 - Set up the Jenkins Pipeline
- Jenkins home → New Item → name it → Pipeline → OK
- Triggers → select **GitHub hook trigger for GITScm polling**
- Pipeline → Definition = **Pipeline from SCM** → SCM = **Git**
- Enter repo URL, select GitHub PAT credentials, Branch: `*/main`
- Save

Step 6.16 - Set up GitHub Webhook
- GitHub repo → Settings → Webhooks → Add webhook
- Payload URL: `http://<your-jenkins-ip>:8080/github-webhook/`
- Content Type: `application/json`
- Click Add webhook

Step 6.17 - Click **Build Now** in Jenkins to start the initial build

Step 6.18 - After a successful build, navigate to `http://<your-loadbalancer-external-ip>` to verify the application

![Jenkins Build](./screenshots/jenkins_build.png)


### Phase 7 - Set up GitOps with GitHub Actions and ArgoCD

Step 7.1 - Create the gitops branch, remove the Jenkinsfile, and create the workflow directory

```
git checkout -b gitops
rm Jenkinsfile
mkdir -p .github/workflows
touch .github/workflows/deploy.yml
```

Step 7.2 - Add the following to deploy.yml

```yaml
name: Deploy to EKS

on:
  push:
    branches:
      - gitops

env:
  AWS_REGION:   <your-region>
  ECR_REPO:     <your-account-id>.dkr.ecr.<your-region>.amazonaws.com/<your-ecr-repo-name>
  CLUSTER_NAME: <your-cluster-name>

jobs:
  build-and-push:
    runs-on: ubuntu-latest

    permissions:
      contents: read
      id-token: write

    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v3
        with:
          role-to-assume: arn:aws:iam::<your-account-id>:role/<your-oidc-role-name>
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build, tag, and push image to ECR
        run: |
          docker build -t $ECR_REPO:latest ./backend
          docker push $ECR_REPO:latest
```

Step 7.3 - Set up OIDC provider in AWS
- IAM → Identity providers → Add provider
- Provider type: OpenID Connect
- Provider URL: `https://token.actions.githubusercontent.com`
- Audience: `sts.amazonaws.com`
- Click Add provider

Step 7.4 - Create IAM role for GitHub Actions
- IAM → Roles → Create role → Trusted entity: Web identity
- Identity provider: `token.actions.githubusercontent.com`
- Audience: `sts.amazonaws.com`
- GitHub organization: your GitHub username
- GitHub repository: `<your-repo-name>`
- GitHub branch: `gitops`
- Attach policies: `AmazonEC2ContainerRegistryPowerUser`, `AmazonEKSClusterPolicy`, `AmazonEKSWorkerNodePolicy`
- Name the role and click Create
- Replace `<your-oidc-role-name>` in deploy.yml with your role name

Step 7.5 - Push to GitHub to trigger the workflow

```
git add .
git commit -m "add GitHub Actions workflow"
git push origin gitops
```

Step 7.6 - Install ArgoCD on the EKS cluster from your local machine

```
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Step 7.7 - Verify ArgoCD pods are running

```
kubectl get pods -n argocd
```

Step 7.8 - Get the initial ArgoCD admin password

```
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Step 7.9 - Access the ArgoCD UI

```
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Navigate to `https://localhost:8080` and log in with username `admin` and the password from Step 7.8.

![ArgoCD](./screenshots/argo_cd.png)

Step 7.10 - Create an ArgoCD application
- Click **New App**
- Application Name: `backend`, Project: `default`, Sync Policy: `Automatic`
- Source: Repository URL: `https://github.com/<your-username>/<your-repo>`, Revision: `gitops`, Path: `helm/backend`
- Destination: Cluster URL: `https://kubernetes.default.svc`, Namespace: `default`
- Click **Create** then **Sync**

Step 7.11 - Verify the deployment

```
kubectl get pods
kubectl get services
```

Step 7.12 - Navigate to `http://<your-loadbalancer-external-ip>` to confirm "Hello, World!" is displaying

## Conclusion
This project successfully demonstrated a full end-to-end DevOps workflow by deploying a containerized Node.js application to AWS EKS using industry-standard tools and practices. Starting from a simple "Hello, World!" Express application, the project covered containerization with Docker, infrastructure provisioning with Terraform, container orchestration with Kubernetes, and automated deployments through two separate CI/CD approaches — Jenkins on the main branch and a GitOps workflow using GitHub Actions and ArgoCD on the gitops branch. The application was made highly available and scalable through EKS node auto-scaling and Horizontal Pod Autoscaling based on CPU and memory utilization.

## Lessons Learned
- **Kubernetes requires more configuration than ECS** — Unlike ECS with Fargate, EKS requires managing node groups, IAM roles, subnet tags, and kubectl access separately. The additional complexity comes with greater flexibility and control.
- **Helm simplifies Kubernetes deployments** — Managing raw YAML manifests becomes difficult at scale. Helm charts allow you to template and reuse deployment configurations across environments.
- **ArgoCD and Jenkins serve different purposes** — Jenkins handles the full CI/CD pipeline while ArgoCD focuses purely on the CD side using a GitOps approach. Both are valid and are often used together in production.
- **Node capacity planning matters** — Running ArgoCD alongside the application exhausted the single node's pod capacity, requiring a second node to be provisioned. Resource planning is critical in real deployments.
- **IAM permissions are granular in EKS** — Connecting kubectl and GitHub Actions to EKS required specific access entries and IAM role configurations that differ from standard AWS IAM patterns.
- **user_data scripts eliminate manual server setup** — Pre-installing Jenkins, Docker, and Java via user_data ensured the Jenkins EC2 was ready on boot without manual intervention.
