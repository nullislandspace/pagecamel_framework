/**
Install npm node eslit typedoc:
wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash

nvm install node
nvm install --lts
npm install --save-dev eslint-plugin-tsdoc
npm install typedoc -D


Doc erstellen:
typedoc --entryPointStrategy expand --exclude "**/*+(.js)" --readme ./src/cxelements/README.md  -out ./docs/cxelements ./src/cxelements --tsconfig tsconfig_debug.json
typedoc --entryPointStrategy expand --exclude "**/*+(.js)" --readme ./src/cxviews/README.md -out ./docs/cxviews ./src/cxviews --tsconfig tsconfig_debug.json 
typedoc --entryPointStrategy expand --exclude "**/*+(.js)" --readme ./src/cxadds/README.md -out ./docs/cxadds ./src/cxadds --tsconfig tsconfig_debug.json

Rene:
 tsc src/cxposmain.ts --target ES6 --module ES6 --strict --removeComments --strictNullChecks --sourceMap --noImplicitAny --outdir out

*/
