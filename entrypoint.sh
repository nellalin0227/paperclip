#!/bin/sh
# Fix volume permissions then switch to node user
chown -R node:node /paperclip
exec su -s /bin/sh node -c 'node --import ./server/node_modules/tsx/dist/loader.mjs server/dist/index.js'
