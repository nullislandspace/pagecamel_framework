#!/bin/bash

# ====Typescript Installation====

# 1. Install nvm
wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# 2. Install latest node js and npm package managing version
nvm install --lts

# 3. check installation
#node --version
#npm --version

# 4. Install typescript
npm install -g typescript

# 5. pchelpers
cd ~/src/pagecamel_framework/lib/PageCamel/Web/Static/pchelpers && npm install && tsc

