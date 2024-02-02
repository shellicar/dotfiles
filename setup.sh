#!/bin/env sh

####################################################
# This script will install common dependencies
# nvm - Managing npm versions
# pnpm - node package manager of choice
# homebrew (OSX) - Package manager for OSX
# gitversion - Semantic versioning
# azure-functions-core-tools - Azure Functions
# docker - Containers
####################################################

SETUP_SCRIPT_NAME="setup.sh"
SETUP_SCRIPT=${0##*/}

if [ "$SETUP_SCRIPT" = "$SETUP_SCRIPT_NAME" ]; then
  echo "Please source this script instead of running it directly."
  echo "e.g.: . ./$SETUP_SCRIPT_NAME"
  return
fi

echo "❔❔❔ Checking dependency status and activation"

SETUP_NVM_VERSION=v0.39.7
SETUP_HOMEBREW_VERSION=HEAD
SETUP_NVM_DEFAULT_VERSION=--lts
SETUP_PNPM_VERSION=latest
SETUP_GITVERSION_VERSION="5.12.0"
SETUP_GITVERSION_FILE=gitversion-linux-x64-${SETUP_GITVERSION_VERSION}.tar.gz
SETUP_GITVERSION_SRC=https://github.com/GitTools/GitVersion/releases/download/${SETUP_GITVERSION_VERSION}/${SETUP_GITVERSION_FILE}

# Determine the environment
SETUP_ARCHITECTURE=""
SETUP_OS="unknown"

case $(uname) in
Darwin) OS="macOS"; SETUP_ARCHITECTURE="osx-arm64" ;;
Linux) OS="linux";  SETUP_ARCHITECTURE="linux-x64" ;;
*)
  echo "Unknown operating system."
  exit 1
  ;;
esac
echo "OS=$OS"

if [ "$OS" = "linux" ]; then
  check_package() {
    dpkg -s $1 > /dev/null 2>&1
  }
else
  check_package() {
    brew list $1 > /dev/null 2>&1
  }
fi

echo "❔ Checking nvm.sh"
# Check if ~/.nvm/nvm.sh exists
if [ -f ~/.nvm/nvm.sh ]; then
  echo "✅ Sourcing ~/.nvm/nvm.sh..."
  . ~/.nvm/nvm.sh
else
  echo "❌ ~/.nvm/nvm.sh does not exist."
fi

echo "❔ Checking nvm command"
# Check if NVM command exists on the path and will run
if ! command -v nvm >/dev/null; then
  echo "❌ NVM is not installed properly, installing"
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/${SETUP_NVM_VERSION}/install.sh | bash
  . ~/.nvm/nvm.sh
else
  echo "✅ NVM is installed properly."
fi


# Install Homebrew on macOS if it's not installed
if [ "$OS" = "macOS" ]; then
  echo "❔ Checking homebrew"
  if ! command -v brew >/dev/null; then
    echo "❌ Homebrew is not installed. Installing now..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/${SETUP_HOMEBREW_VERSION}/HEAD/install.sh)"
  else
    echo "✅ Homebrew is installed."
  fi
fi

if [ -f .nvmrc ]; then
  echo "✅ Installing nvm version: $(cat .nvmrc)"
  nvm install
else
  echo "✅ Installing nvm version: ${SETUP_NVM_DEFAULT_VERSION}"
  nvm install ${SETUP_NVM_DEFAULT_VERSION}
fi


echo "❔ Checking gitversion"
if ! command -v gitversion; then
  echo "❌ Installing gitversion"
  SETUP_TEMP_DIR=$(mktemp -d)
  SETUP_TEMP_FILE=${SETUP_TEMP_DIR}/${SETUP_GITVERSION_FILE}
  
  echo "TEMP_FILE=$SETUP_TEMP_FILE"
  mkdir -p $SETUP_TEMP_DIR
  curl -LJ -o ${SETUP_TEMP_FILE} ${SETUP_GITVERSION_SRC} || return 1
  sudo tar -xvf ${SETUP_TEMP_FILE} -C /usr/local/bin/ || return 2
  sudo chmod 755 /usr/local/bin/gitversion || return 3
  rm -rf ${SETUP_TEMP_DIR} || return 3
  echo "✅ Installed gitversion"

  unset TEMP_DIR TEMP_FILE
else
  echo "✔️ gitversion already installed"
fi


# echo "❔ Checking DOTNET_ROOT"
# if [ -z "$DOTNET_ROOT" ]; then
#   echo "❌ Setting DOTNET_ROOT in .bashrc"
#   echo "export set DOTNET_ROOT=/usr/share/dotnet" >>$HOME/.bashrc
#   DOTNET_ROOT=/usr/share/dotnet
#   echo "✅ Set DOTNET_ROOT"
# else
#   echo "✔️ DOTNET_ROOT already set"
# fi


echo "❔ Checking pnpm"
corepack enable
command -v pnpm
if ! command -v pnpm >/dev/null; then
  echo "❌ Installing pnpm: ${SETUP_PNPM_VERSION}"
  corepack prepare pnpm@${SETUP_PNPM_VERSION} --activate
  echo "✅ Installed pnpm"
else
  echo "✔️ pnpm already installed"
fi



if [ -f .nvmrc ]; then
  echo "✅ Using nvm version: $(cat .nvmrc)"
  nvm use
else
  echo "✅ Using nvm version: ${SETUP_NVM_DEFAULT_VERSION}"
  nvm use ${SETUP_NVM_DEFAULT_VERSION}
fi


echo "❔ Checking Azure Functions Core Tools"
if ! command -v func >/dev/null; then
  echo "❌ Installing Azure Functions Core Tools"

  if [ "$OS" = "macOS" ]; then
    # https://learn.microsoft.com/en-us/azure/azure-functions/functions-run-local?tabs=macos%2Cisolated-process%2Cnode-v4%2Cpython-v2%2Chttp-trigger%2Ccontainer-apps&pivots=programming-language-csharp#install-the-azure-functions-core-tools
    brew tap azure/functions
    brew install azure-functions-core-tools@4
    # if upgrading on a machine that has 2.x or 3.x installed:
    brew link --overwrite azure-functions-core-tools@4
  elif [ "$OS" = "linux" ]; then
    # https://learn.microsoft.com/en-us/azure/azure-functions/functions-run-local?tabs=linux%2Cisolated-process%2Cnode-v4%2Cpython-v2%2Chttp-trigger%2Ccontainer-apps&pivots=programming-language-csharp#install-the-azure-functions-core-tools
    curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
    sudo mv microsoft.gpg /etc/apt/trusted.gpg.d/microsoft.gpg
    sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/microsoft-ubuntu-$(lsb_release -cs)-prod $(lsb_release -cs) main" > /etc/apt/sources.list.d/dotnetdev.list'
    sudo apt-get update
    sudo apt-get install azure-functions-core-tools-4 -y
  else
    echo "Unknown operating system."
    exit 1
  fi
  echo "✅ Installed Azure Functions Core Tools"
else
  echo "✔️ Azure Functions Core Tools already installed"
fi


echo "❔ Checking Docker"
if [ "$OS" = "linux" ]; then
  if ! check_package docker.io; then
    echo "❌ Installing Docker"
    
    sudo apt update
    sudo apt install docker.io -y

    echo "✅ Installed Docker"
  else
    echo "✔️ Docker already installed"
  fi
fi

echo "✅✅✅ Setup completed successfully."

unset SCRIPT_NAME SCRIPT NVM_VERSION HOMEBREW_VERSION NVM_DEFAULT_VERSION PNPM_VERSION GITVERSION_VERSION GITVERSION_FILE GITVERSION_SRC ARCHITECTURE OS
