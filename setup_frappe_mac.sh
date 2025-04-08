#!/bin/bash

set -e

# Function to check if a command exists
command_exists () {
    command -v "$1" >/dev/null 2>&1
}

echo "Checking for Homebrew..."
if ! command_exists brew; then
    echo "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

echo "Installing dependencies via Homebrew..."
brew update
brew install git python@3.11 mariadb redis node yarn

# Add Python to PATH if needed
export PATH="/opt/homebrew/opt/python@3.11/bin:$PATH"

# MariaDB setup
echo "Starting MariaDB..."
brew services start mariadb

echo "Waiting for MariaDB to be ready..."
sleep 5

# MariaDB Config
CONFIG_FILE="/opt/homebrew/etc/my.cnf.d/frappe.cnf"
echo "Setting MariaDB config at $CONFIG_FILE..."
mkdir -p "$(dirname "$CONFIG_FILE")"

cat > "$CONFIG_FILE" <<EOF
[mysqld]
innodb-file-format=barracuda
innodb-file-per-table=1
innodb-large-prefix=1
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
EOF

brew services restart mariadb

# Create MariaDB user if not exists
echo "Creating MariaDB user 'frappe'..."

USER_EXISTS=$(mysql -uroot -e "SELECT User FROM mysql.user WHERE User = 'frappe';" | grep frappe || true)

if [ -z "$USER_EXISTS" ]; then
    mysql -uroot -e "CREATE USER 'frappe'@'localhost' IDENTIFIED BY 'frappe';"
    mysql -uroot -e "GRANT ALL PRIVILEGES ON *.* TO 'frappe'@'localhost';"
    mysql -uroot -e "FLUSH PRIVILEGES;"
    echo "User 'frappe' created with password 'frappe'."
else
    echo "User 'frappe' already exists."
fi

# Bench CLI install
if ! command_exists bench; then
    echo "Installing Frappe Bench CLI..."
    pip3 install frappe-bench
fi

# Ask for folder name
read -p "Enter Frappe folder name: " FOLDER

if [ -d "$FOLDER" ]; then
    echo "Folder $FOLDER already exists. Skipping bench init."
else
    echo "Creating Frappe bench at $FOLDER..."
    bench init "$FOLDER" --frappe-branch version-15
fi

cd "$FOLDER" || exit

# Create site
read -p "Enter site name (e.g., site.local): " SITENAME
bench new-site "$SITENAME" --mariadb-root-password root --admin-password admin

# Get ERPNext
if [ ! -d "apps/erpnext" ]; then
    bench get-app erpnext --branch version-15
fi

bench --site "$SITENAME" install-app erpnext

echo "Setup complete!"
echo "To start the server: cd $FOLDER && bench start"
echo "To access the site: http://$SITENAME"
