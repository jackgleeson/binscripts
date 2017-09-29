#!/bin/bash
pushd $MW_INSTALL_PATH > /dev/null
[ -d extensions.deploy ] && echo "Already local" \
    || { mv extensions extensions.deploy; mv extensions.local extensions; echo "Made local"; }
popd > /dev/null
