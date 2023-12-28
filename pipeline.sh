#!/bin/bash
set -x
set -e

EO=0.34.2

cat > app.eo <<EOT
[args] > app
  QQ.io.stdout > @
    "Hello, world!\n"
EOT

eoc "--parser=${EO}" clean
eoc "--parser=${EO}" link
eoc "--parser=${EO}" --alone dataize app > before.txt

eoc "--parser=${EO}" phi

# Now, you modify/normalize this file:
# .eoc/phi/app.phi

eoc "--parser=${EO}" unphi

cp .eoc/unphi/app.xmir .eoc/2-optimize/app.xmir

eoc "--parser=${EO}" print

cp .eoc/print/app.eo app.eo

eoc "--parser=${EO}" clean

eoc "--parser=${EO}" link
eoc "--parser=${EO}" --alone dataize app > after.txt

if [ "$(cat before.txt)" == "$(cat after.txt)" ]; then
    echo 'SUCCESS'
else
    echo 'FAILURE'
    exit 1
fi