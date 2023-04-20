#tsdoc generation
npx typedoc --entryPointStrategy expand ./src --exclude "**/*+(.js)" -out ./docs/ --tsconfig ./tsconfig.json

