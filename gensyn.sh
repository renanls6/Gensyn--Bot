#!/bin/bash

set -e

# Define environment
ROOT=$PWD

# Color and format codes
RED='\033[0;31m'
GREEN='\033[0;32m'
PURPLE='\033[0;95m'
BLUE='\033[0;94m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Utility functions
print_step() {
    echo -e "\n${CYAN}${BOLD}Step $1: $2${NC}"
}

check_success() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}\u2713 Success!${NC}"
    else
        echo -e "${RED}\u2717 Failed! Please check errors above and try again.${NC}"
        exit 1
    fi
}

trap_cleanup() {
    echo -e "${YELLOW}Cleaning up background processes...${NC}"
    kill $SERVER_PID $NGROK_PID 2>/dev/null || true
    exit 0
}

trap trap_cleanup INT

# Export default environment variables
export PUB_MULTI_ADDRS="${PUB_MULTI_ADDRS:-}" \
       PEER_MULTI_ADDRS="${PEER_MULTI_ADDRS:-/ip4/38.101.215.13/tcp/30002/p2p/QmQ2gEXoPJg6iMBSUFWGzAabS2VhnzuS782Y637hGjfsRJ}" \
       HOST_MULTI_ADDRS="${HOST_MULTI_ADDRS:-/ip4/0.0.0.0/tcp/38331}" \
       IDENTITY_PATH="${IDENTITY_PATH:-$ROOT/swarm.pem}" \
       HF_HUB_DOWNLOAD_TIMEOUT=120

# ASCII Banner
cat << "EOF"
    \033[38;5;45m\033[1m
    ██████  ██            ██████ ██     ██  █████  █████  ███    ███
    ██   ██ ██            ██      ██     ██ ██   ██ ██   ██ ████  ████
    ██████  ██      █████ ████  ██ ██████ █████  ██ ██████
    ██   ██ ██                 ██ ███ ██ ██   ██ ██   ██ ██  ██  ██
    ██   ██ ███████       ██████  ███ ██ ██   ██ ██   ██ ██      ██

           JOIN THE COMMUNITY : https://t.me/Nexgenexplore
EOF

# Ensure modal-login dir exists
if [ ! -d modal-login ]; then
    echo -e "${RED}Directory 'modal-login' not found! Exiting.${NC}"
    exit 1
fi

cd modal-login
source ~/.bashrc

# Install Node.js/npm if missing
if ! command -v npm >/dev/null 2>&1; then
    echo -e "${YELLOW}Installing Node.js and npm...${NC}"
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi

# Install npm dependencies
echo -e "\n${CYAN}Installing frontend dependencies...${NC}"
npm install --legacy-peer-deps

# Start frontend server
npm run dev > server.log 2>&1 &
SERVER_PID=$!

# Detect local port
for i in {1..60}; do
    PORT=$(grep -oE "http://localhost:[0-9]+" server.log | head -n1 | cut -d: -f3)
    [ -n "$PORT" ] && break
    sleep 1

done

[ -z "$PORT" ] && echo -e "${RED}Timeout waiting for frontend to start.${NC}" && kill $SERVER_PID && exit 1

echo -e "${GREEN}Frontend running on port $PORT${NC}"

# Extract ORG_ID
ORG_ID=$(awk -F '"' '/"/{print $(NF-1); exit}' temp-data/userData.json 2>/dev/null || echo "")
[ -n "$ORG_ID" ] && echo -e "ORG_ID: ${BOLD}${ORG_ID}${NC}"

# Detect architecture and OS
ARCH=$(uname -m)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
case $ARCH in
    x86_64) NGROK_ARCH="amd64";;
    arm64|aarch64) NGROK_ARCH="arm64";;
    arm*) NGROK_ARCH="arm";;
    *) echo -e "${RED}Unsupported arch: $ARCH${NC}"; exit 1;;
esac

# Install ngrok
print_step 2 "Installing ngrok"
wget -q "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-${OS}-${NGROK_ARCH}.tgz"
tar -xzf ngrok-v3-stable-${OS}-${NGROK_ARCH}.tgz
sudo mv ngrok /usr/local/bin/
rm ngrok-v3-stable-${OS}-${NGROK_ARCH}.tgz

# Authenticate ngrok
echo -e "${YELLOW}Enter your ngrok authtoken:${NC}"
read -rp "> " NGROK_TOKEN
ngrok authtoken "$NGROK_TOKEN"
check_success

# Start ngrok
print_step 3 "Starting ngrok tunnel"
ngrok http "$PORT" --log=stdout --log-format=json > ngrok_output.log 2>&1 &
NGROK_PID=$!
sleep 5

# Extract ngrok URL
FORWARDING_URL=$(grep -oE '"url":"https://[^"]+' ngrok_output.log | cut -d'"' -f4 | head -n1)

if [ -n "$FORWARDING_URL" ]; then
    echo -e "${GREEN}${BOLD}Access your app at:${NC} ${CYAN}${BOLD}${FORWARDING_URL}${NC}"
else
    echo -e "${RED}Failed to obtain ngrok URL.${NC}"
    kill $NGROK_PID
    exit 1
fi

cd "$ROOT"
echo -e "\n${CYAN}Waiting for user login...${NC}"
while [ ! -f modal-login/temp-data/userData.json ]; do sleep 3; done

# Install Python requirements
echo -e "${CYAN}Installing Python packages...${NC}"
pip install -r requirements-hivemind.txt > /dev/null
pip install -r requirements.txt > /dev/null

# Determine system configuration
if ! command -v nvidia-smi >/dev/null 2>&1 || [ -n "$CPU_ONLY" ]; then
    CONFIG_PATH="$ROOT/hivemind_exp/configs/mac/grpo-qwen-2.5-0.5b-deepseek-r1.yaml"
else
    pip install -r requirements_gpu.txt > /dev/null
    CONFIG_PATH="$ROOT/hivemind_exp/configs/gpu/grpo-qwen-2.5-0.5b-deepseek-r1.yaml"
fi

# Hugging Face token
if [ -n "$HF_TOKEN" ]; then
    HUGGINGFACE_ACCESS_TOKEN=$HF_TOKEN
else
    read -p "Do you want to push to Hugging Face Hub? [y/N] " answer
    case $answer in
        [Yy]*) read -p "Enter your token: " HUGGINGFACE_ACCESS_TOKEN;;
        *) HUGGINGFACE_ACCESS_TOKEN="None";;
    esac
fi

echo -e "\n${GREEN}${BOLD}Ready to start training. Good luck in the swarm!${NC}"
# You can launch training here using: CONFIG_PATH, ORG_ID, HUGGINGFACE_ACCESS_TOKEN
