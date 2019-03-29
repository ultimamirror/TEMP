#!/bin/bash

TMP_FOLDER=$(mktemp -d) 

DAEMON_ARCHIVE=${1:-"https://github.com/apollondeveloper/ApollonCore/releases/download/v2.0.1.0/apollond-2.0.1-x86_64-linux.tar.gz"}
ARCHIVE_STRIP=""
DEFAULT_PORT=12220

COIN_NAME="apollon"
CONFIG_FILE="${COIN_NAME}.conf"
DEFAULT_USER_NAME="ApollonCore2"
DAEMON_FILE="${COIN_NAME}d"
CLI_FILE="${COIN_NAME}-cli" 

BINARIES_PATH=/usr/local/bin
DAEMON_PATH="${BINARIES_PATH}/${DAEMON_FILE}"
CLI_PATH="${BINARIES_PATH}/${CLI_FILE}"

DONATION_ADDRESS="AUyScZXcpzgX7MFvgNAbuYRecftZEDifbG"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

function checks() 
{
  if [[ $(lsb_release -d) != *16.04* ]]; then
    echo -e " ${RED}You are not running Ubuntu 16.04. Installation is cancelled.${NC}"
    exit 1
  fi

  if [[ $EUID -ne 0 ]]; then
     echo -e " ${RED}$0 must be run as root so it can update your system and create the required masternode users.${NC}"
     exit 1
  fi

  if [ -n "$(pidof ${DAEMON_FILE})" ]; then
    read -e -p " $(echo -e The ${COIN_NAME} daemon is already running.${YELLOW} Do you want to add another master node? [Y/N] $NC)" NEW_NODE
    clear
  else
    NEW_NODE="new"
  fi
}

function prepare_system() 
{
  clear
  echo -e "Checking if swap space is required."
  local PHYMEM=$(free -g | awk '/^Mem:/{print $2}')
  
  if [ "${PHYMEM}" -lt "2" ]; then
    local SWAP=$(swapon -s get 1 | awk '{print $1}')
    if [ -z "${SWAP}" ]; then
      echo -e "${GREEN}Server is running without a swap file and has less than 2G of RAM, creating a 2G swap file.${NC}"
      dd if=/dev/zero of=/swapfile bs=1024 count=2M
      chmod 600 /swapfile
      mkswap /swapfile
      swapon -a /swapfile
      echo "/swapfile    none    swap    sw    0   0" >> /etc/fstab
    else
      echo -e "${GREEN}Swap file already exists.${NC}"
    fi
  else
    echo -e "${GREEN}Server running with at least 2G of RAM, no swap file needed.${NC}"
  fi
  
  echo -e "${GREEN}Updating package manager.${NC}"
  apt update
  
  echo -e "${GREEN}Upgrading existing packages, it may take some time to finish.${NC}"
  DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y -qq upgrade 
  
  echo -e "${GREEN}Installing all dependencies for the ${COIN_NAME} coin master node, it may take some time to finish.${NC}"
  apt install -y software-properties-common
  apt-add-repository -y ppa:bitcoin/bitcoin
  apt update
  apt install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
    automake \
    bsdmainutils \
    build-essential \
    curl \
    git \
    htop \
    libboost-chrono-dev \
    libboost-dev \
    libboost-filesystem-dev \
    libboost-program-options-dev \
    libboost-system-dev \
    libboost-test-dev \
    libboost-thread-dev \
    libdb4.8-dev \
    libdb4.8++-dev \
    libdb5.3++ \
    libevent-dev \
    libgmp3-dev \
    libminiupnpc-dev \
    libssl-dev \
    libtool autoconf \
    libzmq5 \
    make \
    pkg-config \
    pwgen \
    software-properties-common \
	tar \
    ufw \
    unzip \
    wget
  clear
  
  if [ "$?" -gt "0" ]; then
      echo -e "${RED}Not all of the required packages were installed correctly.\n"
      echo -e "Try to install them manually by running the following commands:${NC}\n"
      echo -e "apt update"
      echo -e "apt -y install software-properties-common"
      echo -e "apt-add-repository -y ppa:bitcoin/bitcoin"
      echo -e "apt update"
      echo -e "apt install -y make software-properties-common build-essential libtool autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev \
    libboost-program-options-dev libboost-system-dev libboost-test-dev libboost-thread-dev automake git wget curl libdb4.8-dev libdb4.8++-dev \
    bsdmainutils libminiupnpc-dev libgmp3-dev ufw pkg-config libevent-dev libdb5.3++ unzip libzmq5 htop pwgen"
   exit 1
  fi

  clear
}

function deploy_binary() 
{
  if [ -f ${DAEMON_PATH} ]; then
    echo -e " ${GREEN}${COIN_NAME} daemon binary file already exists, using binary from ${DAEMON_PATH}.${NC}"
  else
    cd ${TMP_FOLDER}

    local archive=${COIN_NAME}.tar.gz
    echo -e " ${GREEN}Downloading ${DAEMON_ARCHIVE} and deploying the ${COIN_NAME} service.${NC}"
    wget ${DAEMON_ARCHIVE} -O ${archive}

    tar xvzf ${archive}${ARCHIVE_STRIP} >/dev/null 2>&1
    cp ${DAEMON_FILE} ${CLI_FILE} ${BINARIES_PATH}
    chmod +x ${DAEMON_PATH} >/dev/null 2>&1
    chmod +x ${CLI_PATH} >/dev/null 2>&1
    cd

    rm -rf ${TMP_FOLDER}
  fi
}

function enable_firewall() 
{
  echo -e " ${GREEN}Installing fail2ban and setting up firewall to allow access on port ${PORT}.${NC}"

  apt install ufw -y >/dev/null 2>&1

  ufw disable >/dev/null 2>&1
  ufw allow ${PORT}/tcp comment "${COIN_NAME} Masternode port" >/dev/null 2>&1

  ufw allow 22/tcp comment "SSH port" >/dev/null 2>&1
  ufw limit 22/tcp >/dev/null 2>&1
  
  ufw logging on >/dev/null 2>&1
  ufw default deny incoming >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1

  echo "y" | ufw enable >/dev/null 2>&1
  systemctl enable fail2ban >/dev/null 2>&1
  systemctl start fail2ban >/dev/null 2>&1
}

function add_daemon_service() 
{
  cat << EOF > /etc/systemd/system/${USER_NAME}.service
[Unit]
Description=${COIN_NAME} masternode daemon service
After=network.target
After=syslog.target
[Service]
Type=forking
User=${USER_NAME}
Group=${USER_NAME}
WorkingDirectory=${HOME_FOLDER}
ExecStart=${DAEMON_PATH} -datadir=${HOME_FOLDER} -conf=${HOME_FOLDER}/$CONFIG_FILE -daemon 
ExecStop=${CLI_PATH} stop
Restart=always
RestartSec=3
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

  echo -e " ${GREEN}Starting the ${COIN_NAME} service from ${DAEMON_PATH} on port ${PORT}.${NC}"
  systemctl start ${USER_NAME}.service >/dev/null 2>&1
  
  echo -e " ${GREEN}Enabling the service to start on reboot.${NC}"
  systemctl enable ${USER_NAME}.service >/dev/null 2>&1

  if [[ -z $(pidof $DAEMON_FILE) ]]; then
    echo -e "${RED}The ${COIN_NAME} masternode service is not running${NC}. You should start by running the following commands as root:"
    echo "systemctl start ${USER_NAME}.service"
    echo "systemctl status ${USER_NAME}.service"
    echo "less /var/log/syslog"
    exit 1
  fi
}

function ask_port() 
{
  read -e -p "$(echo -e $YELLOW Enter a port to run the ${COIN_NAME} service on: $NC)" -i ${DEFAULT_PORT} PORT
}

function ask_user() 
{  
  read -e -p "$(echo -e $YELLOW Enter a new username to run the ${COIN_NAME} service as: $NC)" -i ${DEFAULT_USER_NAME} USER_NAME

  if [ -z "$(getent passwd ${USER_NAME})" ]; then
    useradd -m ${USER_NAME}
    local USERPASS=$(pwgen -s 12 1)
    echo "${USER_NAME}:${USERPASS}" | chpasswd

    local home=$(sudo -H -u ${USER_NAME} bash -c 'echo ${HOME}')
    HOME_FOLDER="${home}/.ApollonCore"
        
    mkdir -p ${HOME_FOLDER}
    chown -R ${USER_NAME}: ${HOME_FOLDER} >/dev/null 2>&1
  else
    clear
    echo -e "${RED}User already exists. Please enter another username.${NC}"
    ask_user
  fi
}

function check_port() 
{
  declare -a PORTS

  PORTS=($(netstat -tnlp | awk '/LISTEN/ {print $4}' | awk -F":" '{print $NF}' | sort | uniq | tr '\r\n'  ' '))
  ask_port

  while [[ ${PORTS[@]} =~ ${PORT} ]] || [[ ${PORTS[@]} =~ $[PORT+1] ]]; do
    clear
    echo -e "${RED}Port in use, please choose another port:${NF}"
    ask_port
  done
}

function ask_ip() 
{
  declare -a NODE_IPS
  declare -a NODE_IPS_STR

  for ips in $(netstat -i | awk '!/Kernel|Iface|lo/ {print $1," "}')
  do
    ipv4=$(curl --interface ${ips} --connect-timeout 2 -s4 icanhazip.com)
    NODE_IPS+=(${ipv4})
    NODE_IPS_STR+=("$(echo -e [IPv4] ${ipv4})")

    ipv6=$(curl --interface ${ips} --connect-timeout 2 -s6 icanhazip.com)
    NODE_IPS+=(${ipv6})
    NODE_IPS_STR+=("$(echo -e [IPv6] ${ipv6})")
  done

  if [ ${#NODE_IPS[@]} -gt 1 ]
    then
      echo -e " ${GREEN}More than one IP address found.${NC}"
      INDEX=0
      for ip in "${NODE_IPS_STR[@]}"
      do
        echo -e " [${INDEX}] ${ip}"
        let INDEX=${INDEX}+1
      done
      echo -e " ${YELLOW}Which IP address do you want to use?${NC}"
      read -e choose_ip
      NODEIP=${NODE_IPS[$choose_ip]}
  else
    NODEIP=${NODE_IPS[0]}
  fi
}

function create_config() 
{
  RPCUSER=$(pwgen -s 8 1)
  RPCPASSWORD=$(pwgen -s 15 1)
  cat << EOF > ${HOME_FOLDER}/${CONFIG_FILE}
rpcuser=${RPCUSER}
rpcpassword=${RPCPASSWORD}
rpcallowip=127.0.0.1
rpcport=$[PORT+1]
listen=1
server=1
daemon=1
staking=1
port=${PORT}
EOF
}

function create_key() 
{
  read -e -p "$(echo -e $YELLOW Paste your masternode private key and press ENTER or leave it blank to generate a new private key.$NC)" PRIVKEY

  if [[ -z "${PRIVKEY}" ]]; then
    sudo -u ${USER_NAME} ${DAEMON_PATH} -datadir=${HOME_FOLDER} -conf=${HOME_FOLDER}/${CONFIG_FILE} -daemon >/dev/null 2>&1
    sleep 5

    if [ -z "$(pidof ${DAEMON_FILE})" ]; then
    echo -e "${RED}${COIN_NAME} deamon couldn't start, could not generate a private key. Check /var/log/syslog for errors.${NC}"
    exit 1
    fi

    PRIVKEY=$(sudo -u ${USER_NAME} ${CLI_PATH} -datadir=${HOME_FOLDER} -conf=${HOME_FOLDER}/${CONFIG_FILE} masternode genkey) 
    sudo -u ${USER_NAME} ${CLI_PATH} -datadir=${HOME_FOLDER} -conf=${HOME_FOLDER}/${CONFIG_FILE} stop >/dev/null 2>&1
    sleep 5
  fi
}

function update_config() 
{  
  cat << EOF >> ${HOME_FOLDER}/${CONFIG_FILE}
logtimestamps=1
maxconnections=256
masternode=1
externalip=${NODEIP}
masternodeprivkey=${PRIVKEY}
addnode=172.104.146.184:12218
addnode=167.160.84.197:12218
addnode=95.179.133.80:12218
addnode=80.241.216.99:12218
addnode=212.237.58.199:12218
addnode=209.250.252.141:12218
addnode=178.128.166.126:12218
addnode=149.28.176.80:12218
addnode=67.205.182.137:12218
addnode=104.238.167.168:12218
addnode=207.246.114.56:12218
addnode=139.162.189.224:12218
addnode=45.63.84.70:12218
addnode=80.211.171.235:12218
addnode=209.250.252.141:12218
addnode=178.128.166.126:12218
addnode=149.28.176.80:12218
addnode=67.205.182.137:12218
addnode=104.238.167.168:12218
addnode=207.246.114.56:12218
addnode=139.162.189.224:12218
addnode=45.63.84.70:12218
addnode=80.211.171.235:12218
addnode=167.99.175.49:12218
addnode=144.202.96.205:12218
EOF
  chown ${USER_NAME}: ${HOME_FOLDER}/${CONFIG_FILE} >/dev/null
}

function add_log_truncate()
{
  LOG_FILE="${HOME_FOLDER}/debug.log";

  cat << EOF >> /home/${USER_NAME}/logrotate.conf
${HOME_FOLDER}/*.log {
    rotate 4
    weekly
    compress
    missingok
    notifempty
}
EOF

  if ! crontab -l >/dev/null | grep "/home/${USER_NAME}/logrotate.conf"; then
    (crontab -l ; echo "1 0 * * 1 /usr/sbin/logrotate /home/${USER_NAME}/logrotate.conf --state /home/${USER_NAME}/logrotate-state") | crontab -
  fi
}

function show_output() 
{
 echo
 echo -e "================================================================================================================================"
 echo -e "${GREEN}"
 echo -e "                                                 ${COIN_NAME} installation completed${NC}"
 echo
 echo -e " Your ${COIN_NAME} coin master node is up and running." 
 echo -e "  - it is running as the${GREEN}${USER_NAME}${NC} user, listening on port ${GREEN}${PORT}${NC} at your VPS address ${GREEN}${NODEIP}${NC}."
 echo -e "  - the ${GREEN}${USER_NAME}${NC} password is ${GREEN}${USERPASS}${NC}"
 echo -e "  - the ${COIN_NAME} configuration file is located at ${GREEN}${HOME_FOLDER}/${CONFIG_FILE}${NC}"
 echo -e "  - the masternode privkey is ${GREEN}${PRIVKEY}${NC}"
 echo
 echo -e " You can manage your ${COIN_NAME} service from the cmdline with the following commands:"
 echo -e "  - ${GREEN}systemctl start ${USER_NAME}.service${NC} to start the service for the given user."
 echo -e "  - ${GREEN}systemctl stop ${USER_NAME}.service${NC} to stop the service for the given user."
 echo -e "  - ${GREEN}systemctl status ${USER_NAME}.service${NC} to see the service status for the given user."
 echo
 echo -e " The installed service is set to:"
 echo -e "  - auto start when your VPS is rebooted."
 echo -e "  - rotate your ${GREEN}${LOG_FILE}${NC} file once per week and keep the last 4 weeks of logs."
 echo
 echo -e " You can find the masternode status when logged in as ${USER_NAME} using the command below:"
 echo -e "  - ${GREEN}${CLI_FILE} getinfo${NC} to retreive your nodes status and information"
 echo
 echo -e "   if you are not logged in as ${GREEN}${USER_NAME}${NC} then you can run ${YELLOW}su - ${USER_NAME}${NC} to switch to that user before"
 echo -e "   running the ${GREEN}${CLI_FILE} getinfo${NC} command."
 echo -e "   NOTE: the ${DAEMON_FILE} daemon must be running first before trying this command. See notes above on service commands usage."
 echo
 echo -e " Make sure you keep the information above somewhere private and secure so you can refer back to it." 
 echo -e "${YELLOW} NEVER SHARE YOUR PRIVKEY WITH ANYONE, IF SOMEONE OBTAINS IT THEY CAN STEAL ALL YOUR COINS.${NC}"
 echo
 echo -e "================================================================================================================================"
 echo
 echo
}

function ask_watch()
{  
  read -e -p " $(echo -e ${YELLOW}Do you want to watch the ${COIN_NAME} daemon status whilst it is synchronizing? [Y/N]${NC})" WATCH_CHOICE
  
  if [[ ("${WATCH_CHOICE}" == "y" || "${WATCH_CHOICE}" == "Y") ]]; then
    local cmd=$(echo "${CLI_PATH} -datadir=${HOME_FOLDER} -conf=${HOME_FOLDER}/${CONFIG_FILE} masternode status && ${CLI_PATH} -datadir=${HOME_FOLDER} -conf=${HOME_FOLDER}/${CONFIG_FILE} getinfo")
    watch -n 5 ${cmd}
  fi  
}

function setup_node() 
{
  ask_user
  check_port
  ask_ip
  create_config
  create_key
  update_config
  enable_firewall
  add_daemon_service
  add_log_truncate
  show_output
  ask_watch
}

clear

echo
echo -e "${GREEN}"
echo -e "============================================================================================================="
echo
echo -e "                                     Yb  dP    db    88\"\"Yb"
echo -e "                                      YbdP    dPYb   88__dP"
echo -e "                                      dPYb   dP__Yb  88\"\"\""  
echo -e "                                     dP  Yb dP\"\"\"\"Yb 88" 
echo
echo                          
echo -e "${NC}"
echo -e " This script will automate the installation of your ${COIN_NAME} coin masternode and server configuration by"
echo -e " performing the following steps:"
echo
echo -e "  - Prepare your system with the required dependencies"
echo -e "  - Obtain the latest ${COIN_NAME} masternode files from the ${COIN_NAME} GitHub repository"
echo -e "  - Create a user and password to run the ${COIN_NAME} masternode service"
echo -e "  - Install the ${COIN_NAME} masternode service under the new user [not root]"
echo -e "  - Add DDoS protection using fail2ban"
echo -e "  - Update the system firewall to only allow the masternode port and outgoing connections"
echo -e "  - Rotate and archive the masternode logs to save disk space"
echo
echo -e " You will see ${YELLOW}questions${NC}, ${GREEN}information${NC} and ${RED}errors${NC}. A summary of what has been done will be shown at the end."
echo
echo -e " The files will be downloaded and installed from:"
echo -e " ${GREEN}${DAEMON_ARCHIVE}${NC}"
echo
echo -e " Script created by click2install"
echo -e "  - GitHub: https://github.com/click2install"
echo -e "  - Discord: click2install#9625"
echo -e "  - ${COIN_NAME}: ${DONATION_ADDRESS}"
echo -e "${GREEN}"
echo -e "============================================================================================================="              
echo -e "${NC}"
read -e -p "$(echo -e ${YELLOW} Do you want to continue? [Y/N] ${NC})" CHOICE

if [[ ("${CHOICE}" == "n" || "${CHOICE}" == "N") ]]; then
  exit 1;
fi

checks

if [[ ("${NEW_NODE}" == "y" || "${NEW_NODE}" == "Y") ]]; then
  setup_node
  exit 0
elif [[ "${NEW_NODE}" == "new" ]]; then
  prepare_system
  deploy_binary
  setup_node
else
  echo -e "${GREEN}${COIN_NAME} daemon already running.${NC}"
  exit 0
fi
