AWS DevOps Project 02 — Scalable VPC Architecture

Project: Deploy Scalable VPC Architecture on AWS Cloud
AWS Region used: us-east-1
Level: Beginner-friendly, hands-on AWS / DevOps project

📌 What I Built

In this project, I built a small but realistic AWS network from scratch.

The main idea was to separate the administration network from the application network.

I created:

🏠 A Bastion VPC: 192.168.0.0/16

🏠 An Application VPC: 172.32.0.0/16

🌐 Public and private subnets

🚪 Internet Gateways

🔄 NAT Gateway for private application servers

🔗 AWS Transit Gateway to connect the two VPCs

🖥️ EC2 instances

📈 Auto Scaling Group

⚖️ Application Load Balancer

🎯 Target Group

🔐 IAM role for EC2

🪣 S3 bucket for application/configuration files

🛡️ Security Groups

📊 VPC Flow Logs

☁️ CloudWatch Logs

🔑 AWS Systems Manager Session Manager

🌍 ALB DNS name for public application access

The final traffic flow looked roughly like this:

                         INTERNET
                            |
                            v
                   +----------------+
                   | Application    |
                   | Load Balancer   |
                   +----------------+
                            |
                            v
                 +---------------------+
                 | Application VPC     |
                 | 172.32.0.0/16      |
                 |                     |
                 | Public Subnets     |
                 |       |             |
                 |       | NAT Gateway |
                 |       v             |
                 | Private Subnets    |
                 |       |             |
                 |       v             |
                 | Auto Scaling Group  |
                 | EC2 x 2+           |
                 +---------------------+
                            |
                            |
                    Transit Gateway
                            |
                            |
                            v
                 +---------------------+
                 | Bastion VPC         |
                 | 192.168.0.0/16      |
                 |                     |
                 | Public Subnet       |
                 | Bastion EC2         |
                 +---------------------+

🧠 1. Why I Built It This Way

Before creating anything in AWS, I wanted to understand why each component exists.

A beginner-friendly way to think about the architecture is:

The VPC is the private neighborhood.

A subnet is a smaller street inside that neighborhood.

A route table is a traffic sign telling packets where to go.

An Internet Gateway is the door to the public internet.

A NAT Gateway lets private servers go out to the internet without making them directly reachable from the internet.

A Transit Gateway is like a central road junction connecting different VPCs.

A Security Group is a firewall around an EC2 instance.

A Load Balancer is the front desk that receives requests and sends them to healthy servers.

An Auto Scaling Group keeps the required number of servers running.

CloudWatch Logs stores logs so I can inspect what happened.

Session Manager lets me connect to private EC2 instances without giving them public IP addresses.

🗺️ 2. Network Design

2.1 Bastion VPC

CIDR:

192.168.0.0/16

The Bastion VPC is a separate network used for controlled administration.

The important idea is:

I did not want the application servers to be directly exposed just because I needed administrative access.

The Bastion VPC contains the Bastion host in a public subnet.

The Bastion host can be used as a controlled entry point to the private application environment.

2.2 Application VPC

CIDR:

172.32.0.0/16

This VPC contains the application infrastructure.

The application servers were placed in private subnets.

That means the EC2 application servers do not need public IP addresses.

When they need to reach the internet, for example to download packages or application files, they can use the NAT Gateway.

🔗 3. Transit Gateway

I created an AWS Transit Gateway to connect:

Bastion VPC
     |
     | Transit Gateway
     |
Application VPC

The Transit Gateway is useful because it provides a central way to connect VPCs.

Instead of trying to build complicated direct connections between every network, the Transit Gateway becomes the central connection point.

I also configured the appropriate route tables and VPC routes so traffic could move between the connected networks.

🌐 4. Internet Gateway

I created an Internet Gateway for the VPCs that needed public internet connectivity.

A public subnet needs a route similar to:

Destination     Target
0.0.0.0/0       Internet Gateway

This tells AWS:

"For traffic going anywhere on the internet, send it to the Internet Gateway."

🚪 5. NAT Gateway

The application EC2 instances were placed in private subnets.

A private subnet does not have a direct route to the Internet Gateway.

However, the application servers still needed outbound internet access.

For example:

Downloading packages

Installing Apache

Accessing GitHub

Downloading application/configuration files

So I used a NAT Gateway.

The traffic flow is:

Private EC2
    |
    v
Private Route Table
    |
    v
NAT Gateway
    |
    v
Internet Gateway
    |
    v
Internet

The important security idea is:

The private EC2 instance can initiate outbound traffic, but it is not directly exposed to inbound internet traffic.

🔐 6. Security Groups

I created Security Groups to control which traffic was allowed.

The exact rules should always be adapted to the environment, but the important design was:

Bastion Security Group

Allowed administrative access such as SSH from the required source.

Application Security Group

Allowed:

HTTP traffic for the application

SSH only from the Bastion security boundary when needed

The application servers were not intentionally opened to the entire internet for SSH.

🖥️ 7. Bastion EC2 Instance

I launched a Bastion EC2 instance inside the public subnet of the Bastion VPC.

The Bastion server provides a controlled administrative entry point.

Conceptually:

Administrator
     |
     v
Bastion EC2
     |
     | Transit Gateway
     v
Private Application EC2

This is safer than giving every private application server a public IP address.

🪣 8. S3 Bucket

I created an S3 bucket to hold project/application configuration information.

The EC2 instances were given an IAM role so they could access the required S3 resources without storing AWS access keys directly on the server.

This is an important AWS security principle:

Prefer IAM roles over hardcoding AWS access keys on EC2 instances.

👤 9. IAM Role for EC2

The EC2 instances used an IAM role.

The role was used for services such as:

AWS Systems Manager

S3 access

The EC2 instance receives temporary credentials automatically through the IAM role.

I did not need to put a permanent AWS access key and secret key inside the EC2 user-data script.

🔑 10. Systems Manager Session Manager

I configured the EC2 instances so they could be managed using AWS Systems Manager Session Manager.

This was especially useful for the private instances.

Instead of requiring a public IP address and opening SSH to the world, I could use:

AWS Console
     |
     v
Systems Manager
     |
     v
Private EC2

This made administration of private instances much easier.

📦 11. Launch Template

Instead of manually configuring every application server, I created an EC2 Launch Template.

The Launch Template contains the instructions AWS should use whenever it needs to create a new application server.

It included:

AMI

Instance type

Security Group

IAM instance profile

Key pair

User Data

This is important for Auto Scaling because every new EC2 instance should be configured consistently.

📝 12. Launch Template User Data

The User Data script automatically configured the server when it started.

The script installed Apache, Git, started the web server, and pulled the application/project files.

See:

scripts/launch-template-userdata.sh

The script is intentionally written in a beginner-friendly way with comments explaining what each section does.

Important: The exact Git repository URL and S3 bucket name are environment-specific. Replace the placeholders before using the script in another AWS account.

📈 13. Auto Scaling Group

I created an Auto Scaling Group using the Launch Template.

The project used:

Minimum: 2
Maximum: 4

This means AWS tries to keep at least two application instances available.

If an instance fails, Auto Scaling can replace it.

If more capacity is needed, the group can launch additional instances up to the configured maximum.

This gives the application better availability than relying on a single EC2 server.

🎯 14. Target Group

I created:

DevOps02-App-TG

The Target Group keeps track of the EC2 instances that should receive application traffic.

The Load Balancer sends traffic to the Target Group.

The Target Group then sends that traffic to healthy application instances.

⚖️ 15. Application Load Balancer

I created:

DevOps02-App-ALB

The ALB was placed in public subnets.

Its job is to receive requests from the internet and forward them to the healthy EC2 instances in the Target Group.

The listener was:

HTTP : 80

Forwarding:

ALB
 |
 v
DevOps02-App-TG
 |
 +----> EC2 instance 1
 |
 +----> EC2 instance 2

The ALB DNS name used during testing was:

devops02-app-alb-2112449220.us-east-1.elb.amazonaws.com

I used the ALB DNS name directly for testing because I did not have a custom domain for the lab.

❤️ 16. Health Checks

The Target Group performed health checks against the application instances.

During validation, I confirmed that the target instances became:

Healthy

The important lesson is:

The Load Balancer should send traffic only to instances that pass the health check.

📊 17. VPC Flow Logs

I enabled VPC Flow Logs.

The purpose is to record information about network traffic flowing through the VPC.

The logs were sent to:

DevOps02-VPC-Flow-Logs

I checked the CloudWatch log streams and confirmed that traffic information was being delivered.

Example log streams included ENI-based streams such as:

eni-045f180455ed0bafb-all
eni-0522ec71ed99b0a87-all
eni-0fa1693124daee48b-all

The exact ENI IDs will be different in another deployment.

☁️ 18. CloudWatch

CloudWatch was used for logging and monitoring.

For this project I used CloudWatch to inspect the VPC Flow Logs.

This helped me understand that the AWS network was actually generating and delivering traffic logs.

🧪 19. Testing the Application

After the infrastructure was created, I tested the application using the ALB DNS name.

I opened:

http://devops02-app-alb-2112449220.us-east-1.elb.amazonaws.com

The application loaded successfully.

I also checked the Target Group and confirmed that the application instances were healthy.

🔐 20. Testing Private EC2 Access

I used AWS Systems Manager Session Manager to access the private EC2 instances.

This confirmed that:

The EC2 instances were running.

The IAM role was working.

SSM was working.

The instances did not need public IP addresses for administration.

🛠️ 21. Troubleshooting

One of the useful parts of this project was troubleshooting.

Initially, the ALB did not immediately load in the browser.

Instead of assuming the entire architecture was broken, I checked the components one by one:

Is the ALB active?

Is the listener configured?

Is the Target Group attached?

Are the targets healthy?

Is HTTP/80 allowed by the Security Group?

Are the EC2 instances running?

Are the application servers actually running Apache?

Is the public subnet route pointing to the Internet Gateway?

Is the ALB DNS name correct?

After checking the infrastructure and waiting for the resources to become ready, the ALB became reachable and the application loaded successfully.

The lesson was:

Troubleshooting AWS is much easier when you check one layer at a time instead of changing everything at once.

🧹 22. Cleanup / Teardown

Because AWS resources can cost money, I deleted the infrastructure after recording the project.

The cleanup included:

Application Load Balancer

Auto Scaling resources / application EC2 instances

Bastion EC2

NAT Gateway

Transit Gateway

Application VPC

Bastion VPC

I also checked for remaining resources such as:

Elastic IP addresses

CloudWatch Log Group

S3 bucket

EC2 instances

Load Balancers

Transit Gateway

Unused project resources

⚠️ Important

Do not blindly delete the AWS default VPC.

Only delete resources that belong to this project.

📁 23. Repository Structure

I recommend keeping the GitHub project organized like this:

DevOps-Project-02/
│
├── README.md
│
├── scripts/
│   └── launch-template-userdata.sh
│
├── policies/
│   ├── ec2-s3-readwrite-policy.json
│   └── ec2-ssm-policy-reference.json
│
└── screenshots/
    ├── 01-vpc.png
    ├── 02-subnets.png
    ├── 03-route-tables.png
    ├── 04-transit-gateway.png
    ├── 05-nat-gateway.png
    ├── 06-launch-template.png
    ├── 07-auto-scaling.png
    ├── 08-target-group.png
    ├── 09-load-balancer.png
    ├── 10-session-manager.png
    └── 11-cloudwatch-flow-logs.png

Screenshots are optional in this starter package, but adding them will make the GitHub repository much stronger.

🧾 24. Important Scripts

The repository includes the scripts I used / reconstructed from the deployment steps.

Launch Template User Data

File:

scripts/launch-template-userdata.sh

This script is responsible for configuring a new EC2 instance automatically.

It performs tasks such as:

Updating packages

Installing Apache

Installing Git

Starting Apache

Enabling Apache at boot

Downloading the application files

Creating a simple health-check page

🔑 25. IAM Policies

The repository also contains example IAM policy JSON files.

The policies demonstrate how to give an EC2 role the permissions needed for:

S3 access

Systems Manager

Security warning

Never put:

AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY

inside:

User Data

GitHub

README files

Shell scripts

Public repositories

IAM roles are the preferred approach for EC2.

🧠 26. What I Learned

This project helped me understand AWS networking much better.

The biggest lessons were:

1. VPC design

I learned how to create isolated networks and divide them into public and private subnets.

2. Routing

I learned that simply creating a subnet is not enough. Route tables determine where traffic goes.

3. NAT Gateway

I learned why private servers can need internet access without being directly reachable from the internet.

4. Transit Gateway

I learned how AWS can connect multiple VPCs through a central networking service.

5. Bastion architecture

I learned why administrative access can be separated from application infrastructure.

6. Auto Scaling

I learned how EC2 instances can be created from a common Launch Template and maintained automatically.

7. Load Balancing

I learned how an ALB distributes traffic to healthy instances.

8. IAM

I learned why AWS roles are safer than putting access keys directly on servers.

9. Session Manager

I learned how private EC2 instances can be accessed without exposing SSH directly to the internet.

10. Monitoring

I learned how VPC Flow Logs and CloudWatch can help investigate network activity.

11. Troubleshooting

I learned to troubleshoot layer by layer instead of randomly changing configurations.

12. Cost awareness

I learned that AWS infrastructure should be deleted after a lab when it is no longer needed.

📚 27. Technologies Used

Technology

Purpose

Amazon VPC

Private AWS networking

EC2

Application and Bastion servers

Subnets

Network segmentation

Route Tables

Traffic routing

Internet Gateway

Internet connectivity

NAT Gateway

Outbound internet for private instances

Transit Gateway

Connects VPCs

Security Groups

Instance-level firewall

Launch Template

Repeatable EC2 configuration

Auto Scaling Group

Instance availability and scaling

Application Load Balancer

Public traffic distribution

Target Group

ALB backend targets

IAM

Permissions and access control

S3

Application/configuration storage

Systems Manager

Secure EC2 management

CloudWatch

Logging and monitoring

VPC Flow Logs

Network traffic visibility

Apache

Web server

Git

Source-code retrieval/version control

AWS CLI

AWS resource management

🚀 28. Final Result

The completed architecture successfully demonstrated:

Internet
   |
   v
Application Load Balancer
   |
   v
Auto Scaling Group
   |
   +---- Private EC2
   |
   +---- Private EC2
   |
   v
Application VPC
   |
   | Transit Gateway
   |
   v
Bastion VPC
   |
   v
Bastion EC2

The application was reachable through the ALB, the private EC2 instances were manageable through Session Manager, and VPC Flow Logs were visible in CloudWatch.

🏁 Final Takeaway

This was more than just creating AWS resources.

The main thing I wanted to understand was how the individual AWS services work together.

I started with networking:

VPC → Subnets → Routes → Internet/NAT

Then connected the networks:

Bastion VPC → Transit Gateway → Application VPC

Then built the application layer:

ALB → Target Group → Auto Scaling → EC2

Then added administration and monitoring:

IAM → Session Manager → CloudWatch → VPC Flow Logs

Finally, I tested the architecture and cleaned up the resources.

That gave me hands-on experience with the building blocks used in real AWS DevOps environments.

⚠️ Note About This Repository

This README documents my hands-on implementation and the learning process.

Some values such as:

AMI IDs

Security Group IDs

Subnet IDs

VPC IDs

Account IDs

S3 bucket names

Elastic IPs

Availability Zones

are environment-specific and will be different in another AWS account.
