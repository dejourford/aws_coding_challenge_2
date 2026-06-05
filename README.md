# Tech Challenge 2

## Objective
Deploy a web application using **Docker**, orchestrate it with **AWS EKS**, and set up a **continuous deployment pipeline** using **Jenkins**.

## Tools Used
- **Node.js / Express** — simple web application serving "Hello, World!"
- **Docker** — containerizing the application and its dependencies
- **Amazon ECR** — storing and versioning Docker images
- **Terraform** — provisioning AWS infrastructure (EKS cluster, VPC, ALB, IAM roles)
- **AWS EKS** — orchestrating containers using Kubernetes with Fargate/EC2 nodes
- **Helm** — packaging and deploying the application to Kubernetes
- **Jenkins** — CI/CD pipeline for building, pushing, and deploying the application
- **kubectl** — interacting with the EKS cluster from Jenkins
- **HPA (Horizontal Pod Autoscaler)** — scaling pods based on CPU/memory utilization
- **ALB (Application Load Balancer)** — routing public traffic to the EKS cluster
- **GitHub** — version control and webhook integration with Jenkins
- **GitHub Actions** — GitOps bonus CI pipeline (build + push to ECR)
- **ArgoCD** — GitOps bonus CD, syncing Helm charts to EKS automatically

## Procedure

Phase 1 - Creating the Web Application

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

Step 1.5 - Create a .gitignore file in the project root and add node_modules to it
```
node_modules
.env
npm-debug.log
```

Step 1.6 - Create index.js and write the web application
```
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

Step 1.8 - Navigate to localhost:3000 in the web browser and you should see the "Hello, World!" text

![Web Browser](./screenshots/web_browser.png)


Phase 2 - Containerize the application with Docker

Step 2.1 - Install Docker

```
sudo apt install docker.io -y
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER
```

Step 2.2 - Create a Dockerfile in the backend directory and add the code snippet below
```
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

Step 2.4 - Run the container and navigate to localhost:3000 to verify that "Hello World!" is still displayed.
```
sudo docker run -d --name backend -p 3000:3000 backend-app
```
![Docker Verified](./screenshots/docker_verify.png)


Phase 3 - Push the Docker image to Elastic Container Registry (ECR)

Step 3.1 - Create a Terraform directory in the project root
```
mkdir terraform && cd terraform
touch provider.tf ecr.tf eks.tf variables.tf outputs.tf
```

Step 3.2 - 

## Conclusion

## Lessons Learned
