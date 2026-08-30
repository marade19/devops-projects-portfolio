# DevOps-Project-01 — Build Log & Deployment Notes

> **Note:** This file is separate from the original tutorial's `README.md`,
> which is still sitting untouched in this repo. This document covers what
> I actually built, the problems I hit along the way, and how I solved them.

## What this project is

A replica of [NotHarshhaa/DevOps-Projects — DevOps-Project-01](https://github.com/NotHarshhaa/DevOps-Projects/tree/master/DevOps-Project-01),
a 3-tier Java web application deployed on AWS:

- **Frontend tier:** Nginx behind a public Network Load Balancer, reverse-proxying to the app tier
- **App tier:** Apache Tomcat running a Spring Boot (WAR-packaged) Java login/registration app, behind an *internal* Network Load Balancer
- **Data tier:** Amazon RDS (MySQL)

The two tiers live in **separate VPCs** (`PrimaryVPC` for frontend, `SecondaryVPC` for the app tier),
connected by a **Transit Gateway**, matching the original project's network design.

## Architecture actually built

```
Internet
   │
   ▼
Public NLB (PrimaryVPC, public subnets)
   │
   ▼
Nginx (ASG, PrimaryVPC private subnets)
   │  reverse proxy → InternalTomcatNLB:8080
   ▼
Internal NLB (SecondaryVPC, private subnets)
   │
   ▼
Tomcat (ASG, SecondaryVPC private subnets)
   │  JDBC → RDS
   ▼
RDS MySQL (PrimaryVPC private subnets)

PrimaryVPC (192.168.0.0/16) <──Transit Gateway──> SecondaryVPC (172.32.0.0/16)
```

Deviations from the tutorial's exact numbers (deliberate, called out so they're not mistaken for mistakes):
- RDS sized as `db.t3.micro`, single-AZ (Free Tier eligible) instead of the README's `db.t3.medium` / Multi-AZ
- Specific CIDR ranges and subnet layout are mine (the README describes the pattern, not exact blocks)

## Problems encountered and how I fixed them

### 1. NAT Gateway placed in the wrong subnet + route tables never associated
**Symptom:** EC2 instances showed `unhealthy` in the target group; UserData's `apt-get install nginx` never completed.
**Root cause:** The NAT Gateway was sitting in a subnet that itself had no route to an Internet Gateway, and the "private"/"public" route tables existed but were never actually *associated* with any subnet — every subnet was silently falling back to the VPC's default Main route table, which had no internet route at all.
**Fix:** Tore down all networking and rebuilt it methodically — after every route table change, ran `describe-route-tables` to confirm the route and the subnet association actually landed before moving to the next step. Put the NAT Gateway in a subnet whose route table has `0.0.0.0/0 → Internet Gateway`.

### 2. `awscli` not installable via `apt` on Ubuntu 24.04
**Symptom:** UserData failed with `E: Package 'awscli' has no installation candidate`.
**Fix:** Switched to downloading the official AWS CLI v2 installer directly:
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
```

### 3. Tomcat 9.0.83 tarball 404'd during install
**Symptom:** `wget https://dlcdn.apache.org/tomcat/tomcat-9/v9.0.83/...` returned `404 Not Found`.
**Root cause:** `dlcdn.apache.org` only hosts the *current* release; once a newer patch version ships, older ones move to the permanent archive.
**Fix:** Switched the download URL to `https://archive.apache.org/dist/tomcat/tomcat-9/v9.0.83/...`.

### 4. WAR deployed but Spring Boot never started (served Tomcat's default page)
**Symptom:** Tomcat logs showed the WAR "deploying" in under 500ms with no errors — but hitting the app showed Tomcat's generic welcome page, not the app.
**Root cause:** `MyWebAppApplication.java` only had a `main()` method (fine for embedded/`java -jar` use) but didn't extend `SpringBootServletInitializer`. Without that, an *external* Tomcat has no hook to actually boot the Spring application context — it just unpacks the WAR as an inert set of files.
**Fix:**
```java
public class MyWebAppApplication extends SpringBootServletInitializer {
    @Override
    protected SpringApplicationBuilder configure(SpringApplicationBuilder application) {
        return application.sources(MyWebAppApplication.class);
    }
    public static void main(String[] args) {
        SpringApplication.run(MyWebAppApplication.class, args);
    }
}
```

### 5. Tomcat's own shipped `ROOT/` folder silently won over the app
**Symptom:** Even after fix #4, still saw Tomcat's default welcome page.
**Root cause:** The raw Tomcat tarball ships with its own pre-populated `webapps/ROOT/` directory (the "Congratulations" page). Dropping `dptweb-1.0.war` in as `ROOT.war` next to it wasn't enough — the pre-existing unpacked folder took priority.
**Fix:** Added `rm -rf /opt/tomcat9/webapps/ROOT` to the UserData script, run *before* the WAR is copied in.

### 6. Duplicate servlet fragment — `tomcat-jasper` vs Tomcat's own `tomcat-embed-el`
**Symptom:** Real deployment error this time:
```
IllegalArgumentException: More than one fragment with the name [org_apache_jasper_el] was found.
Duplicate fragments found in [tomcat-embed-el-9.0.83.jar, tomcat-jasper-el-9.0.83.jar]
```
**Root cause:** `pom.xml` explicitly pulled in `tomcat-jasper` (for JSP support), bundling its own `tomcat-jasper-el` jar inside the WAR. The target Tomcat server already ships an equivalent `tomcat-embed-el` jar as part of its core runtime. Both register a fragment with the same identity, and Tomcat refuses to start.
**Fix:** Changed the dependency's scope to `provided` in `pom.xml` (see `pom-xml-changes.md`), so it's available at compile time but excluded from the packaged WAR — letting the target Tomcat's own copy be the only one present.

### 7. Security groups don't work across a Transit Gateway
**Symptom:** `AuthorizeSecurityGroupIngress` failed with `InvalidGroup.NotFound — You have specified two resources that belong to different networks.`
**Root cause:** `--source-group` references only resolve within a single VPC. `FrontendSG` (PrimaryVPC) and `TomcatSG` (SecondaryVPC) can't reference each other by ID even though the Transit Gateway connects their networks.
**Fix:** Used CIDR-block-based security group rules instead of security-group references for every cross-VPC rule (e.g. `TomcatSG` allows port 8080 from `192.168.2.0/24` / `192.168.3.0/24`, the Nginx tier's private subnet ranges).

### 8. Internal NLB health checks failed even with "correct" security groups
**Symptom:** `TomcatTG` showed both targets `unhealthy` / `Target.FailedHealthChecks`, even after confirming Tomcat itself was reachable via `curl` from inside the instance.
**Root cause:** An NLB's health checks originate from network interfaces placed *in the target's own subnets*, not from wherever the caller (Nginx) lives. `TomcatSG` only allowed port 8080 from PrimaryVPC's subnets — it needed to also allow it from SecondaryVPC's own private subnets, where the Internal NLB's health-check ENIs actually sit.
**Fix:** Added `TomcatSG` ingress rules for port 8080 from `172.32.2.0/24` / `172.32.3.0/24` (SecondaryVPC's own private subnets).

## IAM roles: the "attach after the fact" lesson

The frontend (Nginx) instances originally launched with **no IAM role**, which meant SSM Session Manager couldn't reach them at all when I needed to debug inside one. Attaching an IAM instance profile to an *already-running* instance doesn't take effect until the instance reboots (the SSM Agent only picks up new credentials at boot). Lesson applied on the second tier: `TomcatS3Role` / `TomcatS3Profile` (S3 read + SSM) was baked into the Tomcat launch template **from the start**, with no bolt-on step needed.

## Deployment order (see `scripts/` folder for the actual commands)

1. `01-networking-primary-vpc.sh` — PrimaryVPC, subnets, IGW, NAT Gateway, route tables
2. `02-networking-secondary-vpc.sh` — SecondaryVPC, subnets, IGW, NAT Gateway, route tables
3. `03-transit-gateway.sh` — connects the two VPCs
4. `04-security-groups.sh` — FrontendSG, DatabaseSG, TomcatSG
5. `05-rds.sh` — DB subnet group + RDS MySQL instance
6. `06-frontend-tier.sh` — Nginx launch template, ASG, public NLB
7. `07-app-tier.sh` — S3 bucket, Tomcat launch template, ASG, internal NLB
8. `nginx-userdata.sh` / `tomcat-userdata.sh` — the actual boot scripts referenced by the launch templates above (final, working versions — all the fixes above are already applied)

Resource IDs (VPC IDs, subnet IDs, etc.) in these scripts reflect *my* actual AWS account from this build — swap them for your own if reproducing this.

## Database setup

Ran manually via an SSM session into a Tomcat instance (RDS is not publicly accessible by design):
```sql
CREATE DATABASE javaapp;
USE javaapp;

CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_username ON users(username);
CREATE INDEX idx_email ON users(email);
```

## Application code changes

See `pom-xml-changes.md` for the Maven dependency fix, and problem #4 above for the `MyWebAppApplication.java` change.

## Security note

`application.properties` currently has the real RDS master password committed in plaintext locally.
**Before pushing to GitHub**, this needs to be replaced with a placeholder or moved to an environment
variable / AWS Secrets Manager — do not commit real credentials to a public repo.

## Verified working

Confirmed end-to-end via the public NLB's DNS name in a browser: request travels
internet → PublicNLB → Nginx → InternalTomcatNLB → Tomcat → renders the real `dptweb` app page.

## Not yet done / next phase

- **CI/CD (Jenkins + SonarCloud):** intentionally treated as a separate follow-up phase, not part of this
  infrastructure build. This project used manual AWS CLI commands throughout; Jenkins would automate the
  `mvn package` → upload to S3 → trigger ASG refresh pipeline instead.
- Wiring real login credentials into the `users` table (currently only Spring Security's auto-generated
  dev password is active).
