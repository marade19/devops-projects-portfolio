#!/bin/bash
# =============================================================================
# AWS DevOps Project 02 - Launch Template User Data
# =============================================================================
# Purpose:
#   Configure a new EC2 application/web server automatically when it starts.
#
# IMPORTANT:
#   Replace the placeholder GIT_REPO_URL with the repository used by your
#   application before using this in another environment.
# =============================================================================

set -e

echo "===== Starting EC2 bootstrap ====="

# -----------------------------------------------------------------------------
# 1. Update installed packages
# -----------------------------------------------------------------------------
yum update -y

# -----------------------------------------------------------------------------
# 2. Install Apache and Git
# -----------------------------------------------------------------------------
yum install -y httpd git

# -----------------------------------------------------------------------------
# 3. Start Apache
# -----------------------------------------------------------------------------
systemctl enable httpd
systemctl start httpd

# -----------------------------------------------------------------------------
# 4. Remove the default Apache page
# -----------------------------------------------------------------------------
rm -f /var/www/html/index.html

# -----------------------------------------------------------------------------
# 5. Clone the application repository
# -----------------------------------------------------------------------------
# Replace this with your actual Git repository.
GIT_REPO_URL="https://github.com/YOUR-USERNAME/YOUR-REPOSITORY.git"

if git ls-remote "$GIT_REPO_URL" >/dev/null 2>&1; then
    rm -rf /tmp/app-repository
    git clone "$GIT_REPO_URL" /tmp/app-repository

    # Copy application files into Apache's web directory.
    # Adjust this command if your repository has a specific web directory.
    cp -r /tmp/app-repository/. /var/www/html/
else
    echo "WARNING: Git repository could not be reached."
fi

# -----------------------------------------------------------------------------
# 6. Create a simple health-check page.
#    This is useful for testing the Target Group / ALB.
# -----------------------------------------------------------------------------
cat > /var/www/html/health.html <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>DevOps Project 02</title>
</head>
<body>
    <h1>AWS DevOps Project 02</h1>
    <p>Application server is running.</p>
</body>
</html>
EOF

# -----------------------------------------------------------------------------
# 7. Fix ownership and permissions
# -----------------------------------------------------------------------------
chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html

# -----------------------------------------------------------------------------
# 8. Restart Apache so all changes are loaded
# -----------------------------------------------------------------------------
systemctl restart httpd

echo "===== EC2 bootstrap completed ====="
