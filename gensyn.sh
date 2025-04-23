#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Display header
display_header() {
    clear
    echo -e "${CYAN}"
    echo -e " ${BLUE} ██████╗ ██╗  ██╗    ██████╗ ███████╗███╗   ██╗ █████╗ ███╗   ██╗${NC}"
    echo -e " ${BLUE}██╔═████╗╚██╗██╔╝    ██╔══██╗██╔════╝████╗  ██║██╔══██╗████╗  ██║${NC}"
    echo -e " ${BLUE}██║██╔██║ ╚███╔╝     ██████╔╝█████╗  ██╔██╗ ██║███████║██╔██╗ ██║${NC}"
    echo -e " ${BLUE}████╔╝██║ ██╔██╗     ██╔══██╗██╔══╝  ██║╚██╗██║██╔══██║██║╚██╗██║${NC}"
    echo -e " ${BLUE}╚██████╔╝██╔╝ ██╗    ██║  ██║███████╗██║ ╚████║██║  ██║██║ ╚████║${NC}"
    echo -e " ${BLUE}╚═════╝ ╚═╝  ╚═╝    ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═══╝${NC}"
    echo -e "${BLUE}=======================================================${NC}"
    echo -e "${GREEN}       ✨ Bitz Setup Script ⛏️  ✨${NC}"
    echo -e "${GREEN}       ✨ Follow me on X :https://x.com/renanls6  ✨${NC}"
    echo -e "${BLUE}=======================================================${NC}"
}

# ----------- Architecture check (optional) ----------- 
ARCH=$(uname -m)
if [[ "$ARCH" != "x86_64" && "$ARCH" != "aarch64" ]]; then
  echo "❌ Unsupported architecture: $ARCH, exiting."
  exit 1
fi

# ----------- Check and update /etc/hosts ----------- 
echo "🔧 Checking /etc/hosts configuration..."
if ! grep -q "raw.githubusercontent.com" /etc/hosts; then
  echo "📝 Writing GitHub acceleration Hosts entries..."
  sudo tee -a /etc/hosts > /dev/null <<EOL
199.232.68.133 raw.githubusercontent.com
199.232.68.133 user-images.githubusercontent.com
199.232.68.133 avatars2.githubusercontent.com
199.232.68.133 avatars1.githubusercontent.com
EOL
else
  echo "✅ Hosts are configured, skipping."
fi

# ----------- Install dependencies ----------- 
echo "📦 Installing dependencies: curl, git, python3.12, pip, nodejs, yarn, screen..."

# Add Python 3.12 PPA source and install
sudo apt update
sudo apt install -y software-properties-common
sudo add-apt-repository -y ppa:deadsnakes/ppa
sudo apt update
sudo apt install -y python3.12 python3.12-venv python3.12-distutils

# Install other basic tools
sudo apt install -y curl git screen

# Install Node.js (using NodeSource repository)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Install Yarn (via npm)
npm install -g yarn

# ----------- Set default Python3.12 ----------- 
echo "🐍 Setting Python3.12 as the default version..."
echo 'alias python=python3.12' >> ~/.bashrc
echo 'alias python3=python3.12' >> ~/.bashrc
echo 'alias pip=pip3' >> ~/.bashrc
source ~/.bashrc

# ----------- Check Python version ----------- 
PY_VERSION=$(python3 --version | grep "3.12" || true)
if [[ -z "$PY_VERSION" ]]; then
  echo "⚠️ Python version not correctly pointing to 3.12, reloading configuration..."
  source ~/.bashrc
fi
echo "✅ Current Python version: $(python3 --version)"

# ----------- Clone repository ----------- 
if [[ -d "rl-swarm" ]]; then
  echo "⚠️ The rl-swarm folder already exists in the current directory."
  read -p "Do you want to overwrite the existing directory? (y/n): " confirm
  if [[ "$confirm" == [yY] ]]; then
    echo "🗑️ Deleting old directory..."
    rm -rf rl-swarm
  else
    echo "❌ User cancelled the operation, exiting."
    exit 1
  fi
fi

echo "📥 Cloning rl-swarm repository..."
git clone https://github.com/zunxbt/rl-swarm.git

# ----------- Modify configuration files ----------- 
echo "📝 Modifying YAML configuration..."
sed -i 's/max_steps: 20/max_steps: 5/' rl-swarm/hivemind_exp/configs/mac/grpo-qwen-2.5-0.5b-deepseek-r1.yaml
sed -i 's/gradient_accumulation_steps: 8/gradient_accumulation_steps: 1/' rl-swarm/hivemind_exp/configs/mac/grpo-qwen-2.5-0.5b-deepseek-r1.yaml
sed -i 's/max_completion_length: 1024/max_completion_length: 512/' rl-swarm/hivemind_exp/configs/mac/grpo-qwen-2.5-0.5b-deepseek-r1.yaml

echo "📝 Modifying Python startup parameters..."
sed -i 's/startup_timeout=30/startup_timeout=120/' rl-swarm/hivemind_exp/runner/gensyn/testnet_grpo_runner.py

# ----------- Clean port usage ----------- 
echo "🧹 Cleaning up port usage..."
pid=$(lsof -ti:3000) && [ -n "$pid" ] && kill -9 $pid && echo "✅ Killed process on port 3000: $pid" || echo "✅ Port 3000 is not occupied"

# ----------- Start screen session ----------- 
echo "🖥️ Starting and entering screen session gensyn..."

sleep 2
screen -S gensyn bash -c '
  cd rl-swarm || exit 1

  echo "🐍 Creating Python virtual environment..."
  python3.12 -m venv .venv
  source .venv/bin/activate

  echo "🔧 Setting PyTorch MPS environment variables (optional for Linux, can be commented out)..."
  export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0
  export PYTORCH_ENABLE_MPS_FALLBACK=1

  echo "🚀 Starting RL-Swarm..."
  chmod +x run_rl_swarm.sh
  ./run_rl_swarm.sh

  # Deactivate virtual environment if it's active
  if type deactivate &>/dev/null; then
    deactivate
  fi
'
