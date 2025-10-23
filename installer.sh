#!/bin/bash

###############################################################################
# phpIPAM Installation Script for openSUSE/SLES
# Uses Docker with Official phpIPAM Docker Image
###############################################################################
#
# CREDENTIALS & PASSWORDS DOCUMENTATION
# ======================================
#
# This script sets up phpIPAM using Docker containers with:
#
# 1. MYSQL_ROOT_PASSWORD
#    - Purpose: MySQL root password for database administration
#    - Used by: Database container for root user
#    - Security: 32 bytes base64-encoded random string
#
# 2. MYSQL_PASSWORD
#    - Purpose: MySQL password for phpipam database user
#    - Used by: phpIPAM application to connect to database
#    - Security: 32 bytes base64-encoded random string
#
# 3. PHPIPAM_ADMIN_PASSWORD
#    - Purpose: Initial admin user password for phpIPAM web interface
#    - Used by: First login to phpIPAM (username: admin)
#    - Security: 24 bytes base64-encoded random string
#
###############################################################################

set -e  # Exit on any error

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

# Configuration
PHPIPAM_DOCKER_PATH="/opt/phpipam-docker"
MYSQL_ROOT_PASSWORD=""
MYSQL_PASSWORD=""
PHPIPAM_ADMIN_PASSWORD=""

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   phpIPAM Docker Installation Script  ║${NC}"
echo -e "${GREEN}║   For openSUSE/SLES                    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}" 
   exit 1
fi

echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}            PASSWORD CONFIGURATION${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Please configure passwords for your phpIPAM installation."
echo -e "You can enter custom passwords or press ENTER to auto-generate."
echo ""

# MySQL Root Password
echo -e "${BLUE}[1/3] MySQL Root Password${NC}"
echo -e "Used for database administration"
read -s -p "Enter password (or press ENTER to auto-generate): " MYSQL_ROOT_PASSWORD
echo ""
if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
    MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)
    echo -e "${GREEN}✓ Auto-generated MySQL root password${NC}"
else
    echo -e "${GREEN}✓ Using custom MySQL root password${NC}"
fi
echo ""

# MySQL phpIPAM User Password
echo -e "${BLUE}[2/3] MySQL phpIPAM User Password${NC}"
echo -e "Used by phpIPAM to connect to database"
read -s -p "Enter password (or press ENTER to auto-generate): " MYSQL_PASSWORD
echo ""
if [ -z "$MYSQL_PASSWORD" ]; then
    MYSQL_PASSWORD=$(openssl rand -base64 32)
    echo -e "${GREEN}✓ Auto-generated MySQL phpIPAM password${NC}"
else
    echo -e "${GREEN}✓ Using custom MySQL phpIPAM password${NC}"
fi
echo ""

# phpIPAM Admin Password
echo -e "${BLUE}[3/3] phpIPAM Admin Password${NC}"
echo -e "Password for logging into phpIPAM web interface"
echo -e "Username will be: ${GREEN}admin${NC}"
read -s -p "Enter admin password (or press ENTER to auto-generate): " PHPIPAM_ADMIN_PASSWORD
echo ""
if [ -z "$PHPIPAM_ADMIN_PASSWORD" ]; then
    PHPIPAM_ADMIN_PASSWORD=$(openssl rand -base64 24)
    echo -e "${GREEN}✓ Auto-generated admin password${NC}"
else
    echo -e "${GREEN}✓ Using custom admin password${NC}"
fi
echo ""

echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Password configuration complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
sleep 2

echo -e "${YELLOW}[1/6] Updating system packages...${NC}"
zypper refresh
zypper update -y

echo -e "${YELLOW}[2/6] Installing Docker and Docker Compose...${NC}"

# Check if Docker is already installed
if command -v docker &> /dev/null; then
    echo -e "${GREEN}✓ Docker already installed${NC}"
else
    zypper install -y docker docker-compose
fi

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Verify Docker installation
docker --version
docker-compose --version

echo -e "${GREEN}✓ Docker and Docker Compose installed${NC}"

echo -e "${YELLOW}[3/6] Creating phpIPAM directory structure...${NC}"

# Create phpIPAM directory
mkdir -p "$PHPIPAM_DOCKER_PATH"
cd "$PHPIPAM_DOCKER_PATH"

echo -e "${GREEN}✓ Directory created${NC}"

echo -e "${YELLOW}[4/6] Creating Docker Compose configuration...${NC}"

# Create docker-compose.yml
cat > docker-compose.yml <<EOF
version: '3'

services:
  phpipam-db:
    image: mariadb:latest
    container_name: phpipam-db
    restart: unless-stopped
    environment:
      - MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
      - MYSQL_DATABASE=phpipam
      - MYSQL_USER=phpipam
      - MYSQL_PASSWORD=${MYSQL_PASSWORD}
    volumes:
      - phpipam-db-data:/var/lib/mysql
    networks:
      - phpipam-network

  phpipam-web:
    image: phpipam/phpipam-www:latest
    container_name: phpipam-web
    restart: unless-stopped
    ports:
      - "8080:80"
    environment:
      - IPAM_DATABASE_HOST=phpipam-db
      - IPAM_DATABASE_NAME=phpipam
      - IPAM_DATABASE_USER=phpipam
      - IPAM_DATABASE_PASS=${MYSQL_PASSWORD}
      - IPAM_DATABASE_PORT=3306
    depends_on:
      - phpipam-db
    networks:
      - phpipam-network

  phpipam-cron:
    image: phpipam/phpipam-cron:latest
    container_name: phpipam-cron
    restart: unless-stopped
    environment:
      - IPAM_DATABASE_HOST=phpipam-db
      - IPAM_DATABASE_NAME=phpipam
      - IPAM_DATABASE_USER=phpipam
      - IPAM_DATABASE_PASS=${MYSQL_PASSWORD}
      - IPAM_DATABASE_PORT=3306
      - SCAN_INTERVAL=1h
    depends_on:
      - phpipam-db
    networks:
      - phpipam-network

volumes:
  phpipam-db-data:
    driver: local

networks:
  phpipam-network:
    driver: bridge
EOF

echo -e "${GREEN}✓ Docker Compose configuration created${NC}"

# Create .env file for easy reference
cat > .env <<EOF
# phpIPAM Docker Environment Configuration
# ========================================
# Generated on: $(date)

# MySQL Root Password (for database administration)
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}

# MySQL phpIPAM User Password (used by phpIPAM application)
MYSQL_PASSWORD=${MYSQL_PASSWORD}

# phpIPAM Admin Password (for web interface login)
# Username: admin
PHPIPAM_ADMIN_PASSWORD=${PHPIPAM_ADMIN_PASSWORD}

# Database Configuration
MYSQL_DATABASE=phpipam
MYSQL_USER=phpipam
MYSQL_HOST=phpipam-db
MYSQL_PORT=3306
EOF

chmod 600 .env

echo -e "${YELLOW}[5/6] Pulling Docker images and starting phpIPAM...${NC}"
echo -e "${BLUE}This may take several minutes on first run...${NC}"

# Pull all required images
docker-compose pull

# Start all containers
docker-compose up -d

echo -e "${GREEN}✓ Docker containers started${NC}"

echo -e "${YELLOW}[6/6] Waiting for phpIPAM to be ready...${NC}"
echo -e "${BLUE}Waiting for database initialization...${NC}"

# Wait for phpIPAM to be healthy
RETRIES=0
MAX_RETRIES=30
until curl -f http://localhost > /dev/null 2>&1; do
    RETRIES=$((RETRIES+1))
    if [ $RETRIES -eq $MAX_RETRIES ]; then
        echo -e "${RED}phpIPAM failed to start within expected time${NC}"
        echo -e "${YELLOW}Check logs with: docker-compose logs${NC}"
        exit 1
    fi
    echo -e "${BLUE}Waiting for phpIPAM... ($RETRIES/$MAX_RETRIES)${NC}"
    sleep 5
done

echo -e "${GREEN}✓ phpIPAM is ready!${NC}"

# Open firewall for HTTP if firewalld is running
if systemctl is-active --quiet firewalld; then
    echo -e "${YELLOW}Opening firewall for HTTP...${NC}"
    firewall-cmd --permanent --add-service=http
    firewall-cmd --reload
    echo -e "${GREEN}✓ Firewall configured${NC}"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          phpIPAM Docker Installation Complete!            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}phpIPAM is now running at:${NC} ${BLUE}http://localhost${NC}"
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}INITIAL SETUP REQUIRED${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "Open your browser and go to: ${BLUE}http://your-server-ip${NC}"
echo -e "Follow the installation wizard to complete setup."
echo ""
echo -e "${YELLOW}During setup, use these database credentials:${NC}"
echo -e "  Database host: ${GREEN}phpipam-db${NC}"
echo -e "  Database name: ${GREEN}phpipam${NC}"
echo -e "  Database user: ${GREEN}phpipam${NC}"
echo -e "  Database pass: ${GREEN}$MYSQL_PASSWORD${NC}"
echo ""
echo -e "${YELLOW}After installation, login with:${NC}"
echo -e "  Username: ${GREEN}Admin${NC}"
echo -e "  Password: ${GREEN}ipamadmin${NC} (default - change immediately!)"
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}DATABASE CREDENTIALS${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "MySQL Root Password: ${GREEN}$MYSQL_ROOT_PASSWORD${NC}"
echo -e "MySQL phpIPAM Password: ${GREEN}$MYSQL_PASSWORD${NC}"
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}DOCKER COMMANDS${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "View running containers:"
echo -e "  ${GREEN}cd $PHPIPAM_DOCKER_PATH && docker-compose ps${NC}"
echo ""
echo -e "View logs:"
echo -e "  ${GREEN}cd $PHPIPAM_DOCKER_PATH && docker-compose logs -f${NC}"
echo ""
echo -e "Stop phpIPAM:"
echo -e "  ${GREEN}cd $PHPIPAM_DOCKER_PATH && docker-compose stop${NC}"
echo ""
echo -e "Start phpIPAM:"
echo -e "  ${GREEN}cd $PHPIPAM_DOCKER_PATH && docker-compose start${NC}"
echo ""
echo -e "Restart phpIPAM:"
echo -e "  ${GREEN}cd $PHPIPAM_DOCKER_PATH && docker-compose restart${NC}"
echo ""
echo -e "Update phpIPAM:"
echo -e "  ${GREEN}cd $PHPIPAM_DOCKER_PATH && docker-compose pull && docker-compose up -d${NC}"
echo ""
echo -e "${RED}⚠ IMPORTANT: Save the credentials above in a secure location!${NC}"
echo ""

# Save credentials to file
cat > /root/phpipam_credentials.txt <<EOF
╔════════════════════════════════════════════════════════════════════════╗
║                    phpIPAM Installation Credentials                   ║
║                         KEEP THIS FILE SECURE!                         ║
╚════════════════════════════════════════════════════════════════════════╝

Installation Date: $(date)
Installation Path: $PHPIPAM_DOCKER_PATH

═══════════════════════════════════════════════════════════════════════════
MYSQL DATABASE CREDENTIALS
═══════════════════════════════════════════════════════════════════════════

MySQL Root Password: $MYSQL_ROOT_PASSWORD
MySQL phpIPAM User: phpipam
MySQL phpIPAM Password: $MYSQL_PASSWORD

Database Name: phpipam
Database Host: phpipam-db
Database Port: 3306

To connect to MySQL:
  docker exec -it phpipam-db mysql -uroot -p
  (Enter root password when prompted)

═══════════════════════════════════════════════════════════════════════════
PHPIPAM WEB ACCESS
═══════════════════════════════════════════════════════════════════════════

URL: http://your-server-ip

Default Login (CHANGE AFTER FIRST LOGIN):
  Username: Admin
  Password: ipamadmin

⚠️ IMPORTANT: Change the default admin password immediately after first login!

═══════════════════════════════════════════════════════════════════════════
DOCKER COMMANDS
═══════════════════════════════════════════════════════════════════════════

All commands must be run from: $PHPIPAM_DOCKER_PATH

View containers:
  docker-compose ps

View logs:
  docker-compose logs -f phpipam-web

Stop phpIPAM:
  docker-compose stop

Start phpIPAM:
  docker-compose start

Restart phpIPAM:
  docker-compose restart

Update to latest version:
  docker-compose pull
  docker-compose up -d

Backup database:
  docker exec phpipam-db mysqldump -uroot -p$MYSQL_ROOT_PASSWORD phpipam > backup.sql

Restore database:
  docker exec -i phpipam-db mysql -uroot -p$MYSQL_ROOT_PASSWORD phpipam < backup.sql

═══════════════════════════════════════════════════════════════════════════
CONFIGURATION FILES
═══════════════════════════════════════════════════════════════════════════

Docker Compose: $PHPIPAM_DOCKER_PATH/docker-compose.yml
Environment:    $PHPIPAM_DOCKER_PATH/.env
Credentials:    /root/phpipam_credentials.txt (this file)

═══════════════════════════════════════════════════════════════════════════
TROUBLESHOOTING
═══════════════════════════════════════════════════════════════════════════

Cannot access web interface:
  1. Check containers: docker-compose ps
  2. Check logs: docker-compose logs phpipam-web
  3. Check firewall: firewall-cmd --list-all

Database connection errors:
  1. Check database container: docker-compose logs phpipam-db
  2. Verify credentials in docker-compose.yml

Reset everything:
  cd $PHPIPAM_DOCKER_PATH
  docker-compose down -v
  docker-compose up -d

═══════════════════════════════════════════════════════════════════════════
End of phpIPAM Credentials File
═══════════════════════════════════════════════════════════════════════════
EOF

chmod 600 /root/phpipam_credentials.txt

echo -e "${GREEN}Credentials saved to: /root/phpipam_credentials.txt${NC}"
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Installation complete! Access phpIPAM at http://your-server-ip${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
