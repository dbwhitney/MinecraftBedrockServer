#!/bin/bash
# Adapted for my (dbwhitney) use from James A. Chambers 
# Minecraft Server Installation Script - James A. Chambers - https://jamesachambers.com
#
# Instructions: https://jamesachambers.com/minecraft-bedrock-edition-ubuntu-dedicated-server-guide/
# Resource Pack Guide: https://jamesachambers.com/minecraft-bedrock-server-resource-pack-guide/
#
# To run the setup script use:
# curl https://raw.githubusercontent.com/dbwhitney/MinecraftBedrockServer/master/SetupMinecraft.sh | bash
#
# GitHub Repository: https://github.com/dbwhitney/MinecraftBedrockServer

echo "Minecraft Bedrock Server installation script by James A. Chambers"
echo "Latest version always at https://github.com/dbwhitney/MinecraftBedrockServer"
echo "Don't forget to set up port forwarding on your router! The default port is 19132"

# Randomizer for user agent
RandNum=$(echo $((1 + $RANDOM % 5000)))

# Prompt user for installation directory
echo "Please specify the installation directory (press Enter to use the default ~):"
read -p "Directory: " DirName
DirName=${DirName:-$(readlink -e ~)} # Use ~ if no directory is specified

# Ensure directory exists
if [ ! -d "$DirName" ]; then
  echo "Directory does not exist, creating it now..."
  mkdir -p "$DirName"
fi

# Function to read input from user with a prompt
function read_with_prompt {
  variable_name="$1"
  prompt="$2"
  default="${3-}"
  unset $variable_name
  while [[ ! -n ${!variable_name} ]]; do
    read -p "$prompt: " $variable_name </dev/tty
    if [ ! -n "$(which xargs)" ]; then
      declare -g $variable_name=$(echo "${!variable_name}" | xargs)
    fi
    declare -g $variable_name=$(echo "${!variable_name}" | head -n1 | awk '{print $1;}' | tr -cd '[a-zA-Z0-9]._-')
    if [[ -z ${!variable_name} ]] && [[ -n "$default" ]]; then
      declare -g $variable_name=$default
    fi
    echo -n "$prompt : ${!variable_name} -- accept (y/n)?"
    read answer </dev/tty
    if [[ "$answer" == "${answer#[Yy]}" ]]; then
      unset $variable_name
    else
      echo "$prompt: ${!variable_name}"
    fi
  done
}

# Navigate to the installation directory
cd "$DirName" || { echo "Failed to change directory to $DirName. Exiting."; exit 1; }

Update_Scripts() {
  # Remove existing scripts
  rm -f start.sh stop.sh restart.sh fixpermissions.sh revert.sh clean.sh update.sh

  # Download scripts from repository
  for script in start.sh stop.sh restart.sh fixpermissions.sh revert.sh clean.sh update.sh; do
    echo "Grabbing $script from repository..."
    curl -H "Accept-Encoding: identity" -L -o "$script" "https://raw.githubusercontent.com/dbwhitney/MinecraftBedrockServer/master/$script"
    chmod +x "$script"
    sed -i "s:dirname:$DirName:g" "$script"
    sed -i "s:servername:$ServerName:g" "$script"
    sed -i "s:userxname:$UserName:g" "$script"
    sed -i "s<pathvariable<$PATH<g" "$script"
  done
}

Update_Service() {
  # Update Minecraft server service
  echo "Configuring Minecraft $ServerName service..."
  sudo curl -H "Accept-Encoding: identity" -L -o /etc/systemd/system/$ServerName.service "https://raw.githubusercontent.com/dbwhitney/MinecraftBedrockServer/master/minecraftbe.service"
  sudo chmod 644 /etc/systemd/system/$ServerName.service
  sudo sed -i "s:userxname:$UserName:g" /etc/systemd/system/$ServerName.service
  sudo sed -i "s:dirname:$DirName:g" /etc/systemd/system/$ServerName.service
  sudo sed -i "s:servername:$ServerName:g" /etc/systemd/system/$ServerName.service

  if [ -e server.properties ]; then
    sed -i "/server-port=/c\server-port=$PortIPV4" server.properties
    sed -i "/server-portv6=/c\server-portv6=$PortIPV6" server.properties
  fi

  sudo systemctl daemon-reload

  echo -n "Start Minecraft server at startup automatically (y/n)?"
  read answer </dev/tty
  if [[ "$answer" != "${answer#[Yy]}" ]]; then
    sudo systemctl enable "$ServerName.service"
    # Automatic reboot at 4am configuration
    TimeZone=$(cat /etc/timezone)
    CurrentTime=$(date)
    echo "Your time zone is currently set to $TimeZone.  Current system time: $CurrentTime"
    echo "You can adjust/remove the selected reboot time later by typing crontab -e or running SetupMinecraft.sh again."
    echo -n "Automatically restart and backup server at 4am daily (y/n)?"
    read answer </dev/tty
    if [[ "$answer" != "${answer#[Yy]}" ]]; then
      croncmd="$DirName/minecraftbe/$ServerName/restart.sh 2>&1"
      cronjob="0 4 * * * $croncmd"
      (
        crontab -l | grep -v -F "$croncmd"
        echo "$cronjob"
      ) | crontab -
      echo "Daily restart scheduled.  To change time or remove automatic restart type crontab -e"
    fi
  fi
}

Fix_Permissions() {
  echo "Setting server file permissions..."
  sudo ./fixpermissions.sh -a >/dev/null
}

Check_Dependencies() {
  # Install dependencies required to run Minecraft server in the background
  if command -v apt-get &>/dev/null; then
    echo "Updating apt.."
    sudo DEBIAN_FRONTEND=noninteractive apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -yqq

    echo "Checking and installing dependencies.."
    for package in curl unzip screen net-tools gawk openssl xargs pigz; do
      if ! command -v "$package" &>/dev/null; then 
        sudo DEBIAN_FRONTEND=noninteractive apt-get install "$package" -yqq; 
      fi
    done

    CurlVer=$(apt-cache show libcurl4 | grep Version | awk 'NR==1{ print $2 }')
    if [[ "$CurlVer" ]]; then
      sudo DEBIAN_FRONTEND=noninteractive apt-get install libcurl4 -yqq
    else
      CurlVer=$(apt-cache show libcurl3 | grep Version | awk 'NR==1{ print $2 }')
      if [[ "$CurlVer" ]]; then 
        sudo DEBIAN_FRONTEND=noninteractive apt-get install libcurl3 -yqq; 
      fi
    fi

    CurlVer=$(apt-cache show libssl3 | grep Version | awk 'NR==1{ print $2 }')
    if [[ "$CurlVer" ]]; then 
      sudo DEBIAN_FRONTEND=noninteractive apt-get install libssl3 -yqq
    fi

    sudo DEBIAN_FRONTEND=noninteractive apt-get install libc6 libcrypt1 -yqq

    SSLVer=$(apt-cache show libssl1.1 | grep Version | awk 'NR==1{ print $2 }')
    if [[ "$SSLVer" ]]; then
      sudo DEBIAN_FRONTEND=noninteractive apt-get install libssl1.1 -yqq
    else
      CPUArch=$(uname -m)
      if [[ "$CPUArch" == *"x86_64"* ]]; then
        echo "No libssl1.1 available in repositories -- attempting manual install"

        sudo curl -o libssl.deb -k -L https://github.com/dbwhitney/Legendary-Bedrock-Container/raw/main/libssl1-1.deb
        sudo dpkg -i libssl.deb
        sudo rm libssl.deb
        SSLVer=$(apt-cache show libssl1.1 | grep Version | awk 'NR==1{ print $2 }')
        if [[ "$SSLVer" ]]; then
          echo "Manual libssl1.1 installation successful!"
        else
          echo "Manual libssl1.1 installation failed."
        fi
      fi
    fi

    # Double check curl since libcurl dependency issues can sometimes remove it
    if ! command -v curl &>/dev/null; then sudo DEBIAN_FRONTEND=noninteractive apt-get install curl -yqq; fi
    echo "Dependency installation completed"
  else
    echo "Warning: apt was not found.  You may need to install curl, screen, unzip, libcurl4, openssl, libc6, and libcrypt1 with your package manager for the server to start properly!"
  fi
}

Update_Server() {
  # Retrieve latest version of Minecraft Bedrock dedicated server
  echo "Checking for the latest version of Minecraft Bedrock server..."
  curl -H "Accept-Encoding: identity" -L -o "bedrock-server.zip" "https://minecraft.net/en-us/download/server/bedrock"
  if [[ -f "bedrock-server.zip" ]]; then
    echo "Unzipping the latest server files..."
    unzip -o "bedrock-server.zip"
    rm "bedrock-server.zip"
    echo "Minecraft Bedrock server installation completed!"
  else
    echo "Error: Failed to download the server zip file."
  fi
}

# Call the functions to execute them in order
read_with_prompt "UserName" "What is the username you would like to run the Minecraft server under (default is your current username)?" "$(whoami)"
read_with_prompt "ServerName" "What is the name you would like to give your Minecraft server?" "Minecraft"
read_with_prompt "PortIPV4" "What is the IPV4 port for your server (default is 19132)?" "19132"
read_with_prompt "PortIPV6" "What is the IPV6 port for your server (default is 19133)?" "19133"

Check_Dependencies
Update_Server
Update_Scripts
Update_Service
Fix_Permissions

echo "Setup completed. You can now start your Minecraft server using './start.sh'."
