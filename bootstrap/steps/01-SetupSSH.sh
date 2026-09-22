#!/usr/bin/env bash

# this script must run on server side to setup ssh (as root/user has sudo permissions)

# update/upgrade system
# install sshopen-server
# add user with sudo permissions

# why not just ssh on server and run it?
#   openssh-server is not installed on server and after it's installed, root not permited to ssh
#   so, these commands must run manually on the server

echo "[+] Start Updating system"
apt update -y

apt upgrade -y

echo "=============================="
echo "System has been updated successfuly."
echo "=============================="

echo "=============================="
echo "[+] Start Installing openssh-server"
echo "=============================="

apt install openssh-server sudo -y

systemctl enable --now ssh


echo "=============================="
echo "[+] adding admin user"
echo "=============================="

useradd admin -m -s /bin/bash -G sudo

passwd admin


echo "=============================="
echo "[=] System Updated"
echo "[=] SSH Installed"
echo "[=] Admin User Added"
echo "=============================="

