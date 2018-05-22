#!/bin/bash

#=========================#
# Configuring environment #
#=========================#
TMP_FOLDER=$(mktemp -d)
CONFIG_FILE='crowdcoin.conf'
#CONFIGFOLDER='/home/crowdcoin/.crowdcoincore' 
COIN_DAEMON='crowdcoind'
COIN_CLI='crowdcoin-cli'
COIN_TX='crowdcoin-tx'
COIN_PATH='/usr/local/bin/'
COIN_REPO='https://github.com/crowdcoinChain/Crowdcoin.git'
COIN_TGZ='https://github.com/crowdcoinChain/Crowdcoin/releases/download/1.1.0/Crowdcoin_command_line_binaries_linux_1.1.tar.gz'
COIN_ZIP=$(echo $COIN_TGZ | awk -F'/' '{print $NF}')
COIN_NAME='CrowdCoin'
COIN_USER='crowdcoin'
COIN_PORT=12875
RPC_PORT=12876
MYIP=$(curl -s4 icanhazip.com)

# Setup colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
#===================#
# End configuration #
#===================#

# Step 1)
# Initial check if system is compatible and can be used as MN
function checks() {
if [[ $(lsb_release -d) != *16.04* ]]; then
  echo -e "${RED}You are not running Ubuntu 16.04. Installation is cancelled.${NC}"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}$0 must be run as root.${NC}"
   exit 1
fi

if [ -n "$(pidof $COIN_DAEMON)" ] || [ -e "$COIN_DAEMOM" ] ; then
  echo -e "${RED}$COIN_NAME is already installed.${NC}"
  exit 1
fi
}

# Step 2)
# Create the user to install Master Node code
function createUser() {
  echo "Creating $COIN_USER"
  useradd $COIN_USER -m -c "CrowdCoin MN user"
  compile_error
  echo -e "${GREEN}Setting up sudo for $COIN_USER ${NC}"
  usermod -aG sudo $COIN_USER
  echo -e "${GREEN}To access your new user, as root use ${RED}'sudo - $COIN_USER'${GREEN}"
  echo -e "${GREEN}You can setup a password to login directly using: ${RED}'passwd $COIN_USER'${NC}"
  echo -e "${GREEN}To run commands as root using your $COIN_USER user, use ${RED}'sudo <command>'${NC}"
  sleep 3
  # Get user home and config folder based on user created
  CONFIGFOLDER=$(eval echo ~$COIN_USER/.crowdcoincore)
  USER_HOME=$(eval echo ~$COIN_USER)
  echo "Master Node will be installed on $CONFIGFOLDER"
  read a
}

# Step 3)
# Download required packages and prepare the system
function prepare_system() {
echo -e "Prepare the system to install ${GREEN}$COIN_NAME${NC} master node."
apt-get update >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get update > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y -qq upgrade >/dev/null 2>&1
apt install -y software-properties-common >/dev/null 2>&1
echo -e "${GREEN}Adding bitcoin PPA repository"
apt-add-repository -y ppa:bitcoin/bitcoin >/dev/null 2>&1
echo -e "Installing required packages, it may take some time to finish.${NC}"
apt-get update >/dev/null 2>&1
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" make software-properties-common \
build-essential libtool autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev libboost-program-options-dev \
libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake ufw git wget curl libdb4.8-dev bsdmainutils libdb4.8++-dev \
libminiupnpc-dev libgmp3-dev pkg-config libevent-dev libboost-all-dev libdb5.3++ libzmq5 unzip fail2ban >/dev/null 2>&1
if [ "$?" -gt "0" ];
  then
    echo -e "${RED}Not all required packages were installed properly. Try to install them manually by running the following commands:${NC}\n"
    echo "apt-get update"
    echo "apt -y install software-properties-common"
    echo "apt-add-repository -y ppa:bitcoin/bitcoin"
    echo "apt-get update"
    echo 'apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" make software-properties-common \
build-essential libtool autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev libboost-program-options-dev \
libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake ufw git wget curl libdb4.8-dev bsdmainutils libdb4.8++-dev \
libminiupnpc-dev libgmp3-dev ufw pkg-config libevent-dev libboost-all-dev libdb5.3++ libzmq5 unzip fail2ban'
 exit 1
fi
clear
}

# Step 4)
# Create swap file for virtual memory
function create_swap() {
 echo -e "Checking if swap space is needed."
 PHYMEM=$(free -g|awk '/^Mem:/{print $2}')
 SWAP=$(free -g|awk '/^Swap:/{print $2}')
 if [ "$PHYMEM" -lt "2" ] && [ -n "$SWAP" ]
 then
    echo -e "${RED}Server is running with less than 2G of RAM without SWAP, do you want to create a 2G swap file?${NC}."
    read -p "(Y)es / (N)o " -n 1 -r ANSWER
    echo ""
    if [[ $ANSWER =~ ^[Yy]$ ]]
    then
      fallocate -l 2G /swapfile
      chmod 600 /swapfile
      mkswap /swapfile
      swapon /swapfile
      echo -e "${GREEN}Configuring /etc/fstab...${NC}"
      echo " "  >> /etc/fstab 
      echo "/swapfile none swap sw 0 0" >> /etc/fstab
    else
        echo -e "${GREEN}No swap file created! Be advised your MN can not run properly on low memory system.${NC}"
    fi
 else
  echo -e "${GREEN}No swap file needed.${NC}"
 fi
 clear
}


# Compile Masternode from source code (can take longer...)
function compile_node() {
  echo -e "Prepare to compile $COIN_NAME"
  git clone $COIN_REPO $TMP_FOLDER >/dev/null 2>&1
  compile_error
  cd $TMP_FOLDER
  chmod +x ./autogen.sh
  chmod +x ./share/genbuild.sh
  chmod +x ./src/leveldb/build_detect_platform
  ./autogen.sh
  compile_error
  ./configure
  compile_error
  make
  compile_error
  make install
  compile_error
  strip $COIN_PATH$COIN_DAEMON $COIN_PATH$COIN_CLI $COIN_PATH$COIN_TX
  rm -rf $TMP_FOLDER >/dev/null 2>&1
  clear
}

# Downloading the compiled binaries
function download_node() {
  echo -e "Prepare to download $COIN_NAME binaries"
  cd $TMP_FOLDER
  wget -q $COIN_TGZ
  tar xvzf $COIN_ZIP --strip-components 1
  compile_error
  mv $COIN_DAEMON $COIN_CLI $COIN_TX $COIN_PATH
  chmod +x $COIN_PATH$COIN_DAEMON $COIN_PATH$COIN_CLI $COIN_PATH$COIN_TX
  chown $COIN_USER:$COIN_USER $COIN_PATH$COIN_DAEMON $COIN_PATH$COIN_CLI $COIN_PATH$COIN_TX
  rm -r $TMP_FOLDER >/dev/null 2>&1
  clear
}

# Create system service for MN 
function configure_systemd() {
  cat << EOF > /etc/systemd/system/$COIN_NAME.service
[Unit]
Description=$COIN_NAME service
After=network.target

[Service]
User=$COIN_USER
Group=$COIN_USER
Type=forking
WorkingDirectory=$CONFIGFOLDER
ExecStart=$COIN_PATH$COIN_DAEMON -daemon -conf=$CONFIGFOLDER/$CONFIG_FILE -datadir=$CONFIGFOLDER
ExecStop=-$COIN_PATH$COIN_CLI -conf=$CONFIGFOLDER/$CONFIG_FILE -datadir=$CONFIGFOLDER stop

Restart=always
PrivateTmp=true
TimeoutStopSec=60s
TimeoutStartSec=10s
StartLimitInterval=120s
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  sleep 3
  systemctl start $COIN_NAME.service
  systemctl enable $COIN_NAME.service >/dev/null 2>&1

  if [[ -z "$(ps axo cmd:100 | egrep $COIN_DAEMON)" ]]; then
    echo -e "${RED}$COIN_NAME is not running${NC}, please investigate. You should start by running the following commands as root:"
    echo -e "${GREEN}systemctl start $COIN_NAME.service"
    echo -e "systemctl status $COIN_NAME.service"
    echo -e "less /var/log/syslog${NC}"
    exit 1
  fi
}

# Create <COIN>.conf configuration file
function create_config() {
  mkdir $CONFIGFOLDER >/dev/null 2>&1
  RPCUSER=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n1)
  RPCPASSWORD=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w22 | head -n1)
  cat << EOF > $CONFIGFOLDER/$CONFIG_FILE
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD
rpcallowip=127.0.0.1
rpcport=$RPC_PORT
rpcthreads=8
listen=1
server=1
daemon=1
staking=0
discover=1
port=$COIN_PORT
EOF
}

# Create masternode private key
function create_key() {
  echo -e "Enter your ${RED}$COIN_NAME Masternode Private Key${NC}. Leave it blank to generate a new ${RED}Masternode Private Key${NC} for you:"
  read -e COINKEY
  if [[ -z "$COINKEY" ]]; then
  $COIN_PATH$COIN_DAEMON -daemon
  sleep 30
  if [ -z "$(ps axo cmd:100 | grep $COIN_DAEMON)" ]; then
   echo -e "${RED}$COIN_NAME server couldn not start. Check /var/log/syslog for errors.{$NC}"
   exit 1
  fi
  COINKEY=$($COIN_PATH$COIN_CLI masternode genkey)
  if [ "$?" -gt "0" ];
    then
    echo -e "${RED}Wallet not fully loaded. Let us wait and try again to generate the Private Key${NC}"
    sleep 60
    COINKEY=$($COIN_PATH$COIN_CLI masternode genkey)
  fi
  $COIN_PATH$COIN_CLI stop
fi
clear
}

# Update COIN configuration file with master node private key and additional nodes.
function update_config() {
  sed -i 's/daemon=1/daemon=0/' $CONFIGFOLDER/$CONFIG_FILE
  cat << EOF >> $CONFIGFOLDER/$CONFIG_FILE
#logintimestamps=1
#maxconnections=256
#bind=$MYIP
externalip=$MYIP:$COIN_PORT
masternodeprivkey=$COINKEY
masternode=1
addnode=84.17.23.43:12875
addnode=18.220.138.90:12875
addnode=86.57.164.166:12875
addnode=86.57.164.146:12875
addnode=18.217.78.145:12875
addnode=23.92.30.230:12875
addnode=35.190.182.68:12875
addnode=80.209.236.4:12875
addnode=91.201.40.89:12875
EOF
}

# Setup VPS Firewall
function enable_firewall() {
  echo -e "Installing and setting up firewall to allow ingress on port ${GREEN}$COIN_PORT${NC}"
  ufw allow $COIN_PORT/tcp comment "$COIN_NAME MN port" >/dev/null
  ufw allow ssh comment "SSH" >/dev/null 2>&1
  ufw limit ssh/tcp >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1
  echo "y" | ufw enable >/dev/null 2>&1
  systemctl enable fail2ban 
  systemctl start fail2ban
}


# Get automatically your VPS public IP
function get_ip() {
  declare -a NODE_IPS
  for ips in $(netstat -i | awk '!/Kernel|Iface|lo/ {print $1," "}')
  do
    NODE_IPS+=($(curl --interface $ips --connect-timeout 2 -s4 icanhazip.com))
  done

  if [ ${#NODE_IPS[@]} -gt 1 ]
    then
      echo -e "${GREEN}More than one IP. Please type 0 to use the first IP, 1 for the second and so on...${NC}"
      INDEX=0
      for ip in "${NODE_IPS[@]}"
      do
        echo ${INDEX} $ip
        let INDEX=${INDEX}+1
      done
      read -e choose_ip
      MYIP=${NODE_IPS[$choose_ip]}
  else
    MYIP=${NODE_IPS[0]}
  fi
}

# Check for errors
function compile_error() {
if [ "$?" -gt "0" ];
 then
  echo -e "${RED}$COIN_NAME - Last Command was not successful executed ( status "$?"), Please investigate.${NC}"
  exit 1
fi
}

# Final 
function important_information() {
 echo
 echo -e "================================================================================================================================"
 echo -e "$COIN_NAME Masternode is up and running listening on port ${RED}$COIN_PORT${NC}."
 echo -e "Configuration file is: ${RED}$CONFIGFOLDER/$CONFIG_FILE${NC}"
 echo -e "Start: ${RED}sudo systemctl start $COIN_NAME.service${NC}"
 echo -e "Stop: ${RED}sudo systemctl stop $COIN_NAME.service${NC}"
 echo -e "VPS_IP:PORT ${RED}$MYIP:$COIN_PORT${NC}"
 echo -e "MASTERNODE PRIVATEKEY is: ${RED}$COINKEY${NC}"
 echo -e "Please check ${RED}$COIN_NAME${NC} is running with the following command: ${RED}sudo systemctl status $COIN_NAME.service${NC}"
 echo -e "================================================================================================================================"
}

function setupSentinel() {
# Install python 
apt-get update
apt-get -y install python-virtualenv

# Clone sentinel from git and configure it
cd $CONFIGFOLDER
git clone https://github.com/crowdcoinChain/sentinelLinux.git && cd sentinelLinux
export LC_ALL=C
apt install virtualenv
virtualenv ./venv
./venv/bin/pip install -r requirements.txt

# Setup configuration path on sentinel
cd $CONFIGFOLDER/sentinelLinux
sed -i 's/dash_conf=/#dash_conf=/' sentinel.conf
echo "dash_conf=$CONFIGFOLDER/$CONFIG_FILE" >> sentinel.conf
}

# Configure COIN user crontab to run sentinel
function setupCrontab() {
echo -e "${GREEN}Configuring and installing crontab for user $COIN_USER ${NC}"
cd $CONFIGFOLDER/sentinelLinux
crontab -l -u $COIN_USER > tmpcron.txt
echo -e "* * * * * cd $CONFIGFOLDER/sentinelLinux && ./venv/bin/python bin/sentinel.py > /dev/null 2>&1" >> tmpcron.txt
echo -e "${GREEN}Activating crontab for user $COIN_USER ${NC}"
crontab -u $COIN_USER tmpcron.txt
crontab -l -u $COIN_USER
}

# Setup owner and group to the COIN user
function setPermissions() {
  echo -e "${GREEN}Setting owner/group for user $COIN_USER ${NC}"
  chown $COIN_USER:$COIN_USER $USER_HOME -R
}

function setup_node() {
echo "get_ip"
read a
  get_ip
echo "create_config"
read a
  create_config
echo "create_key"
read a
  create_key
echo "update_config"
read a
  update_config
echo "enable_firewall"
read a
  enable_firewall
echo "configure_systemd"
read a
  configure_systemd
echo "setupSentinel"
read a
  setupSentinel
echo "setupCrontab"
read a
  setupCrontab
echo "setPermissions"
read a
  setPermissions
echo "important_information"
read a
  important_information
}

##### Main #####
clear

echo "checks"
read a
checks

echo "create user"
read a
createUser

echo "prepare_system"
read a
prepare_system

echo "create_swap"
read a
create_swap

echo "compile_node"
read a
#compile_node

echo "setup_node"
read a
setup_node

