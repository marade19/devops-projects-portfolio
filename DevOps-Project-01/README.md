# # DevOps Project 01 — Java Login App: Multi-Tier AWS Deployment with Jenkins CI/CD

![AWS Architecture](https://imgur.com/b9iHwVc.png)


![3-tier Architecture Diagram](https://imgur.com/3XF0tlJ.png)

---

# Project Overview

## Introduction

This project demonstrates the deployment of a production-grade Java web application using AWS's robust 3-tier architecture. The implementation follows cloud-native best practices, ensuring high availability, scalability, and security across all application tiers.

### Key Features

- **High Availability**: Multi-AZ deployment with automated failover
- **Auto Scaling**: Dynamic resource allocation based on demand
- **Security**: Defense-in-depth approach with multiple security layers
- **Monitoring**: Comprehensive logging and monitoring setup
- **Cost Optimization**: Efficient resource utilization and management

## Required Accounts and Tools

### 1. AWS Account Setup
- Create an [AWS Free Tier Account](https://aws.amazon.com/free/)
- Install AWS CLI v2
  ```bash
  # For Linux
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip
  sudo ./aws/install

  # For macOS
  brew install awscli

  # Configure AWS CLI
  aws configure
  ```

### 2. Development Tools
- **Git**: Version control system
  ```bash
  # For Linux
  sudo apt-get update
  sudo apt-get install git

  # For macOS
  brew install git
  ```

### 3. CI/CD Integration
- **SonarCloud Account**
  - Sign up at [SonarCloud](https://sonarcloud.io/)
  - Generate authentication token
  - Configure project settings:
    ```bash
    # Add to pom.xml
    <properties>
        <sonar.projectKey>your_project_key</sonar.projectKey>
        <sonar.organization>your_organization</sonar.organization>
        <sonar.host.url>https://sonarcloud.io</sonar.host.url>
    </properties>
    ```

- **JFrog Artifactory**
  - Create account on [JFrog Cloud](https://jfrog.com/start-free/)
  - Set up Maven repository
  - Configure authentication:
    ```xml
    <!-- settings.xml -->
    <servers>
        <server>
            <id>jfrog-artifactory</id>
            <username>${env.JFROG_USERNAME}</username>
            <password>${env.JFROG_PASSWORD}</password>
        </server>
    </servers>
    ```

End-to-end DevOps pipeline that builds, scans, and deploys a Java (Spring Boot/Tomcat) login application onto a multi-tier, multi-VPC AWS architecture — fully automated with Jenkins, SonarCloud, S3, and an Auto Scaling Group.

---

## 📐 Architecture Overview

Two VPCs (primary and secondary) connected via a Transit Gateway, with a public-facing frontend tier, a private application tier running Tomcat behind an Auto Scaling Group, and an RDS database. Build artifacts are shipped through S3, and deployments are rolled out via ASG Instance Refresh.

![DevOps Project 01 3D architecture diagram]

<img width="217" height="150" alt="architecture-3d" src="https://github.com/user-attachments/assets/a004ec64-01bd-4000-bd8a-70d10f4ecc7f" />

**Traffic flow:** Internet → Public NLB → NGINX (frontend tier) → Tomcat app tier (ASG) → RDS.
**Deployment flow:** Jenkins builds the WAR → uploads it to S3 → triggers an ASG Instance Refresh → new instances pull the latest artifact on boot (via user-data) → Jenkins verifies the app responds with HTTP 200 through the NLB.

---

## 🧰 Tech Stack

| Layer            | Tool / Service                                   |
|-------------------|--------------------------------------------------|
| Source control     | GitHub                                            |
| CI/CD              | Jenkins (Declarative Pipeline)                    |
| Build              | Maven, JDK 21                                     |
| Code quality       | SonarCloud                                        |
| Artifact storage   | Amazon S3                                         |
| Compute            | EC2 Auto Scaling Groups (frontend: NGINX, app: Tomcat) |
| Database           | Amazon RDS                                        |
| Networking         | Two VPCs + Transit Gateway, public/private subnets |
| Load balancing     | Network Load Balancer (public-facing)             |
| Provisioning       | Bash + AWS CLI scripts (no Terraform)             |

---

## 📁 Repository Structure

```
DevOps-Project-01/
├── Java-Login-App/                     # Spring Boot / Java source, builds to dptweb-1.0.war
├── Jenkinsfile                         # CI/CD pipeline definition
└── scripts/
    ├── 01-networking-primary-vpc.sh    # Primary VPC, subnets, IGW/NAT
    ├── 02-networking-secondary-vpc.sh  # Secondary VPC, subnets
    ├── 03-transit-gateway.sh           # Transit Gateway creation
    ├── 03-transit-gateway-continue.sh  # TGW attachments / route table updates
    ├── 04-security-groups.sh           # Security groups (frontend, app, db)
    ├── 05-rds.sh                       # RDS instance + subnet group
    ├── 06-frontend-tier.sh             # NGINX ASG + Launch Template + NLB
    ├── 07-app-tier.sh                  # Tomcat ASG + Launch Template
    ├── 08-init-db.sh                   # DB schema/user initialization
    ├── 09-verify-db.sh                 # DB connectivity check
    ├── nginx-userdata.sh / nginx-userdata-runtime.sh
    ├── tomcat-userdata.sh / tomcat-userdata-runtime.sh
    ├── cleanup-duplicate-vpc.sh / cleanup-duplicate-vpc-part2.sh
    └── *.env                           # Captured resource IDs per stage (VPC IDs, SG IDs, etc.)
```

Each `NN-*.sh` script writes the IDs of the resources it creates into a matching `*.env` file (e.g. `primary-vpc.env`, `security-groups.env`, `rds.env`). Later scripts and the teardown script source these files instead of hardcoding IDs.

---

## 🚀 Step-by-Step: Building the Infrastructure

Run the scripts **in numeric order** from the `scripts/` directory. Each step depends on IDs exported by the previous one.

### Step 1 — Primary VPC networking
```bash
./01-networking-primary-vpc.sh
```
Creates the primary VPC, public and private subnets, Internet Gateway, NAT Gateway, and route tables. Resource IDs are saved to `primary-vpc.env`.

### Step 2 — Secondary VPC networking
```bash
./02-networking-secondary-vpc.sh
```
Creates the secondary VPC and its subnets, saved to `secondary-vpc.env`.

### Step 3 — Transit Gateway
```bash
./03-transit-gateway.sh
./03-transit-gateway-continue.sh
```
Provisions the Transit Gateway, attaches both VPCs, and updates route tables so the primary and secondary VPCs can route to each other. Output saved to `transit-gateway.env`.

### Step 4 — Security groups
```bash
./04-security-groups.sh
```
Creates the security groups for the frontend tier, app tier, and database tier, saved to `security-groups.env`.

### Step 5 — RDS database
```bash
./05-rds.sh
```
Provisions the RDS instance and its DB subnet group, saved to `rds.env`.

### Step 6 — Frontend tier (NGINX)
```bash
./06-frontend-tier.sh
```
Creates the NGINX Launch Template (using `nginx-userdata.sh` / `nginx-userdata-runtime.sh`), the frontend Auto Scaling Group, and the public Network Load Balancer. Saved to `frontend-tier.env`.

### Step 7 — App tier (Tomcat)
```bash
./07-app-tier.sh
```
Creates the Tomcat Launch Template (using `tomcat-userdata.sh` / `tomcat-userdata-runtime.sh`) and the app-tier Auto Scaling Group (`TomcatASG`) that ultimately runs the deployed `.war`. Saved to `app-tier.env`.

### Step 8 — Initialize the database
```bash
./08-init-db.sh
```
Connects to RDS and applies the schema/seed data the Java Login App needs (e.g. the `users` table, `db-password` credential used by the app).

### Step 9 — Verify database connectivity
```bash
./09-verify-db.sh
```
Sanity-checks that the app tier can reach RDS before you start deploying application code.

> If you ever end up with duplicate/orphaned VPC resources from a re-run, `cleanup-duplicate-vpc.sh` and `cleanup-duplicate-vpc-part2.sh` remove them safely.

---

## 🔁 CI/CD Pipeline (Jenkinsfile)

The Jenkins pipeline lives at `DevOps-Project-01/Jenkinsfile` and runs six stages:

1. **Checkout** — pulls `main` from `https://github.com/marade19/devops-projects-portfolio.git` using the `github-credentials` credential.
2. **Build** — runs `mvn clean package` inside `DevOps-Project-01/Java-Login-App`, producing `target/dptweb-1.0.war`.
3. **SonarCloud Analysis** — runs the Sonar Maven plugin against the `marade19` SonarCloud organization using the `sonarcloud-token` credential.
4. **Upload Artifact to S3** — uploads `dptweb-1.0.war` to the S3 bucket defined in `BUCKET_NAME`, authenticated via the `aws-credentials` Jenkins credential (must be of **kind "AWS Credentials"**, not "Username with password" — see Gotchas below).
5. **Deploy - ASG Instance Refresh** — starts an `aws autoscaling start-instance-refresh` against `TOMCAT_ASG`, then polls `describe-instance-refreshes` every 15 seconds until the refresh reports `Successful` (or fails/cancels the build if it doesn't).
6. **Verify Deployment** — waits 30 seconds, then curls `PUBLIC_NLB_DNS` up to 6 times (15s apart) checking for an HTTP 200 response before marking the pipeline green.

### Required Jenkins credentials

| Credential ID       | Kind                     | Used for                          |
|----------------------|--------------------------|------------------------------------|
| `github-credentials`  | Username/password or PAT | Checking out the repo             |
| `sonarcloud-token`    | Secret text              | Authenticating to SonarCloud       |
| `db-password`         | Secret text              | App's database password            |
| `aws-credentials`     | **AWS Credentials**      | S3 upload + ASG instance refresh   |

### Required environment values (top of Jenkinsfile)

```groovy
AWS_DEFAULT_REGION = 'us-east-1'
BUCKET_NAME        = '<your-artifact-bucket>'
TOMCAT_ASG         = '<your-app-tier-asg-name>'
PUBLIC_NLB_DNS     = '<your-public-nlb-dns-name>'
```
Get the ASG name with:
```bash
aws autoscaling describe-auto-scaling-groups \
  --query "AutoScalingGroups[*].AutoScalingGroupName" --output table
```

### Running the pipeline
1. Update the four environment values above and the `aws-credentials` withCredentials blocks in the Jenkinsfile.
2. Commit and push:
   ```bash
   git add DevOps-Project-01/Jenkinsfile
   git commit -m "Add S3 upload and ASG refresh stages"
   git push origin main
   ```
3. In Jenkins: open `devops-project-01-pipeline` → **Build Now** → watch **Console Output**.

### Gotchas learned the hard way
- **Credential type mismatch**: `ERROR: Credentials 'aws-credentials' is of type 'Username with password' where 'AmazonWebServicesCredentials' was expected` means the credential was created as the wrong kind. Recreate it in Jenkins as kind **AWS Credentials** with the same ID so you don't need to touch the Jenkinsfile.
- The `withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: '...']])` block only works with that AWS Credentials kind — it will not accept Secret text or Username/password credentials.
- If you'd rather store the key pair as two Secret text credentials (`aws-access-key-id` / `aws-secret-access-key`), skip `withCredentials` entirely and export them directly in the `environment {}` block — the AWS CLI picks them up automatically.

---

## ✅ Verifying a Deployment Manually

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://<PUBLIC_NLB_DNS>/
```
A `200` confirms the frontend tier is reachable and serving the app end-to-end through NGINX → Tomcat → RDS.

---

## 🧹 Tearing Down the Infrastructure

Because this project is built with plain scripts (no Terraform), teardown is also script-driven. Delete resources in this order to avoid dependency errors — top of the stack down to networking:

1. **Auto Scaling Groups** (frontend + app tier) — deleting these terminates their EC2 instances.
2. **Launch Templates** for both tiers.
3. **Load Balancer + Target Groups** (public NLB).
4. **RDS instance + DB subnet group.**
5. **Transit Gateway attachments**, then the **Transit Gateway** itself.
6. **Security groups** (frontend, app, db).
7. **NAT Gateways, Internet Gateways, Elastic IPs.**
8. **Subnets and both VPCs** (secondary first, then primary).
9. **S3 bucket** — empty it before deleting.

### Automated teardown script

```bash
#!/bin/bash
set -e

AWS_REGION="us-east-1"
ASG_NAME="your-asg-name"
LAUNCH_TEMPLATE_NAME="your-launch-template-name"
ALB_NAME="your-alb-name"
TARGET_GROUP_NAME="your-target-group-name"
S3_BUCKET_NAME="your-s3-bucket-name"

export AWS_DEFAULT_REGION=$AWS_REGION

echo "Starting infrastructure teardown in $AWS_REGION..."

# 1. Auto Scaling Group
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name "$ASG_NAME" \
  --min-size 0 --max-size 0 --desired-capacity 0 2>/dev/null || true
aws autoscaling delete-auto-scaling-group \
  --auto-scaling-group-name "$ASG_NAME" --force-delete 2>/dev/null || true

# 2. Launch Template
aws ec2 delete-launch-template \
  --launch-template-name "$LAUNCH_TEMPLATE_NAME" 2>/dev/null || true

# 3. Load Balancer + Target Group
ALB_ARN=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" \
  --query "LoadBalancers[0].LoadBalancerArn" --output text 2>/dev/null || echo "")
[ -n "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ] && aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN"

TG_ARN=$(aws elbv2 describe-target-groups --names "$TARGET_GROUP_NAME" \
  --query "TargetGroups[0].TargetGroupArn" --output text 2>/dev/null || echo "")
[ -n "$TG_ARN" ] && [ "$TG_ARN" != "None" ] && aws elbv2 delete-target-group --target-group-arn "$TG_ARN"

# 4. S3 bucket
aws s3 rm "s3://$S3_BUCKET_NAME" --recursive 2>/dev/null || true
aws s3api delete-bucket --bucket "$S3_BUCKET_NAME" --region "$AWS_REGION" 2>/dev/null || true

# 5. Security groups (dynamically discovered by naming convention)
SECURITY_GROUP_IDS=($(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=devops-project-01-*" \
  --query "SecurityGroups[*].GroupId" --output text))
for SG_ID in "${SECURITY_GROUP_IDS[@]}"; do
  aws ec2 delete-security-group --group-id "$SG_ID" 2>/dev/null || \
    echo "Could not delete $SG_ID yet — check for remaining dependencies."
done

echo "Teardown complete!"
```

> Delete the Transit Gateway attachments/gateway and the two VPCs manually (or add matching CLI calls) since their exact IDs depend on your `.env` files — source `transit-gateway.env`, `primary-vpc.env`, and `secondary-vpc.env` at the top of the script to fill in the ARNs/IDs automatically instead of hardcoding them.

### Verify teardown
Check the **AWS Cost Explorer** or **Billing Dashboard** over the next 24 hours to confirm usage drops to $0, and confirm in the EC2/RDS/VPC consoles that instance, database, and load balancer counts are all at zero.

---

## 📝 Notes

- Rebuilding the environment from scratch after a teardown just means re-running `01` through `09` in order, then re-running the Jenkins pipeline once the new `TOMCAT_ASG` name and `PUBLIC_NLB_DNS` are updated in the Jenkinsfile.
- Keep `*.env` files out of version control if they ever contain sensitive account-specific identifiers — `.gitignore` them and regenerate on each provisioning run.
> [!Important]
> This documentation is continuously evolving. For the latest updates, please check the repository regularly.
