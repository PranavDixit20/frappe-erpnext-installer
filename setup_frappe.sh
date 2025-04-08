#!/bin/bash

set -e

# Function to check if a command exists
command_exists () {
    command -v "$1" >/dev/null 2>&1
}

# Step 1: Prerequisite setup
echo "Checking for prerequisites..."

REQUIRED_CMDS=("git" "python3" "pip3" "node" "npm" "yarn" "redis-server" "bench" "mysql")

MISSING=false
for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command_exists $cmd; then
        MISSING=true
        break
    fi
done

if [ "$MISSING" = true ]; then
    echo "Installing prerequisites..."
    
    sudo apt update
    sudo apt install -y git python3-dev python3-pip python3-setuptools python3-venv \
        redis-server mariadb-server libmysqlclient-dev curl

    # Node and Yarn
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt install -y nodejs
    sudo npm install -g yarn

    # Bench CLI
    pip3 install frappe-bench
else
    echo "All prerequisites already installed."
fi

# Step 2: Configure MariaDB
echo "Configuring MariaDB for Frappe..."

sudo tee /etc/mysql/conf.d/frappe.cnf > /dev/null <<EOF
[mysqld]
innodb-file-format=barracuda
innodb-file-per-table=1
innodb-large-prefix=1
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
EOF

sudo systemctl restart mariadb

# Step 3: Create MariaDB user (if not exists)
echo "Creating MariaDB user 'frappe'..."

DB_USER_EXISTS=$(sudo mysql -uroot -e "SELECT User FROM mysql.user WHERE User = 'frappe';" | grep frappe || true)

if [ -z "$DB_USER_EXISTS" ]; then
    sudo mysql -uroot -e "CREATE USER 'frappe'@'localhost' IDENTIFIED BY 'frappe';"
    sudo mysql -uroot -e "GRANT ALL PRIVILEGES ON *.* TO 'frappe'@'localhost';"
    sudo mysql -uroot -e "FLUSH PRIVILEGES;"
    echo "User 'frappe' created with password 'frappe'."
else
    echo "User 'frappe' already exists."
fi

# Step 4: Ask for Frappe folder
read -p "Enter Frappe folder name: " FOLDER

if [ -d "$FOLDER" ]; then
    echo "Folder $FOLDER already exists. Skipping bench init."
else
    echo "Creating Frappe bench at $FOLDER..."
    bench init "$FOLDER" --frappe-branch version-15
fi

cd "$FOLDER" || exit

# Step 5: Create site
read -p "Enter site name (e.g., site.local): " SITENAME
bench new-site "$SITENAME" --mariadb-root-password root --admin-password admin

# Step 6: Get ERPNext app and install
if [ ! -d "apps/erpnext" ]; then
    bench get-app erpnext --branch version-15
fi

bench --site "$SITENAME" install-app erpnext

# Step 7: Done
echo "Setup complete!"
echo "To start your server, run:"
echo "cd $FOLDER && bench start"
echo "Then, access your site at http://$SITENAME"
