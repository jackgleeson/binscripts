#!/bin/bash
pushd $MW_INSTALL_PATH > /dev/null;
[ -d extensions.local ] && echo "Already deploy" \
    || { mv extensions extensions.local; mv extensions.deploy extensions; echo "Made deploy"; }
popd > /dev/null;

