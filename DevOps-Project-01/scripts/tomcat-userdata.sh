#!/bin/bash
# tomcat-userdata.sh
# Runs at boot on every Tomcat app-tier EC2 instance.
#
# This is the FINAL version after three rounds of fixes (see BUILD-LOG.md
# problems #2, #3, #5 for the full story):
#   - awscli isn't apt-installable on Ubuntu 24.04 -> install AWS CLI v2 directly
#   - Tomcat 9.0.83 was pulled from the "current" dlcdn mirror -> use the
#     permanent archive.apache.org mirror instead
#   - the Tomcat tarball ships its own default webapps/ROOT/ folder, which
#     silently wins over a dropped-in ROOT.war unless removed first

apt-get update -y
apt-get install -y openjdk-11-jdk wget unzip

# Install AWS CLI v2 (not available via apt on Ubuntu 24.04)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# Install Tomcat 9 (permanent archive mirror, not the rotating "current" one)
cd /opt
wget https://archive.apache.org/dist/tomcat/tomcat-9/v9.0.83/bin/apache-tomcat-9.0.83.tar.gz
tar -xzf apache-tomcat-9.0.83.tar.gz
mv apache-tomcat-9.0.83 tomcat9
rm apache-tomcat-9.0.83.tar.gz

# Remove the default shipped ROOT app so it doesn't conflict with our WAR
rm -rf /opt/tomcat9/webapps/ROOT

# Deploy the WAR file (bucket/key from 07-app-tier.sh)
/usr/local/bin/aws s3 cp s3://devopsproject01-artifacts-1787865399/dptweb-1.0.war /opt/tomcat9/webapps/ROOT.war

# Start Tomcat
chmod +x /opt/tomcat9/bin/*.sh
/opt/tomcat9/bin/startup.sh
