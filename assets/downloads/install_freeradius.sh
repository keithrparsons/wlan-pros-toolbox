#!/bin/bash

set -e

echo "🔹 Installing FreeRADIUS..."
sudo apt-get update
sudo apt-get install -y freeradius freeradius-utils

echo "🔹 Configuring clients.conf..."
sudo bash -c 'cat >> /etc/freeradius/3.0/clients.conf <<EOF

client 172.16.99.0/24 {
    secret = secretwlanpros
}

client 10.10.0.0/16 {
    secret = secretwlanpros
}

client 192.168.20.0/24 {
    secret = secretwlanpros
}
EOF'

sudo sed -i 's/secret = testing123/secret = secretwlanpros/' /etc/freeradius/3.0/clients.conf

echo "🔹 Configuring EAP..."
sudo sed -i 's/default_eap_type = md5/default_eap_type = peap/' /etc/freeradius/3.0/mods-enabled/eap

echo "🔹 Configuring MSCHAP..."
sudo sed -i 's/#use_mppe = no/use_mppe = yes/' /etc/freeradius/3.0/mods-enabled/mschap
sudo sed -i 's/#require_encryption = yes/require_encryption = yes/' /etc/freeradius/3.0/mods-enabled/mschap
sudo sed -i 's/#require_strong = yes/require_strong = yes/' /etc/freeradius/3.0/mods-enabled/mschap

echo "🔹 Adding users..."
sudo bash -c 'cat >> /etc/freeradius/3.0/users <<EOF

student01 Cleartext-Password := "password01"
    Reply-Message := "Hello, %{User-Name}"

student02 Cleartext-Password := "password02"
    Reply-Message := "Hello, %{User-Name}"

student03 Cleartext-Password := "password03"
    Reply-Message := "Hello, %{User-Name}"

student04 Cleartext-Password := "password04"
    Reply-Message := "Hello, %{User-Name}"

student05 Cleartext-Password := "password05"
    Reply-Message := "Hello, %{User-Name}"

student06 Cleartext-Password := "password06"
    Reply-Message := "Hello, %{User-Name}"

student07 Cleartext-Password := "password07"
    Reply-Message := "Hello, %{User-Name}"

student08 Cleartext-Password := "password08"
    Reply-Message := "Hello, %{User-Name}"

student09 Cleartext-Password := "password09"
    Reply-Message := "Hello, %{User-Name}"

student10 Cleartext-Password := "password10"
    Reply-Message := "Hello, %{User-Name}"
EOF'

echo "🔹 Allowing RADIUS through firewall..."
sudo ufw allow 1812/udp || true

echo "🔹 Restarting FreeRADIUS..."
sudo systemctl restart freeradius

echo "🔹 Checking status..."
sudo systemctl status freeradius --no-pager

echo "🔹 Running test..."
radtest student01 password01 localhost 0 secretwlanpros

echo "✅ FreeRADIUS installation and configuration complete!"