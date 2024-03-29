set -euo pipefail

if ! [ -d node_modules ]; then npm i; fi

shopt -s expand_aliases
EO="0.35.8"
alias eo="npx eoc --parser=${EO}"

shopt -s extglob

DIR=try-unphi

function prepare_directory {
    printf "\nPrepare the $DIR directory\n\n"

    mkdir -p $DIR/phi
    mkdir -p $DIR/init

    rm -rf $DIR/tmp
    mkdir -p $DIR/tmp

    rm -rf $DIR/unphi
    mkdir -p $DIR/unphi
}

function enter_directory {
    printf "\nEnter the $DIR directory\n\n"

    cd $DIR
}

function init_eoc {
    printf "\nGenerate an initial .eoc directory\n\n"

    cd init

    if [ ! -d .eoc ]; then
        cat <<EOM > test.eo
+alias org.eolang.io.stdout
+architect yegor256@gmail.com
+home https://github.com/objectionary/eo
+tests
+package org.eolang
+version 0.0.0

# Test.
[] > prints-itself
  gt. > @
    length.
      as-phi $
    0
EOM
        eo phi
    fi

    rm -f .eoc/phi/test.phi
    rm -f .eoc/2-optimize/test.xmir

    cd ..
}

function unphi {
    printf "\nUnphi\n\n"

    cd tmp

    cp -r ../init/.eoc .
    cp -r ../phi/* .eoc/phi

    eo unphi

    cp -r .eoc/unphi/!(org) .eoc/2-optimize

    eo print

    cp -r .eoc/print/!(org) ../unphi

    cd ..
}

prepare_directory
enter_directory
init_eoc
unphi
