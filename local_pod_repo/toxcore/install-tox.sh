#!/bin/bash

_HOME2_=$(dirname $0)
export _HOME2_
_HOME_=$(cd $_HOME2_;pwd)
export _HOME_

echo $_HOME_
cd $_HOME_

GIT_PATH="toxcore-git"
OUTPUT="toxcore"

DIRS=(
    "toxcore"
    "toxav"
    "toxdns"
    "toxencryptsave"
)

echo "Removing old toxcore directory"
rm -rf $OUTPUT
mkdir $OUTPUT

rm -Rf $GIT_PATH/
git clone https://github.com/TokTok/c-toxcore $GIT_PATH/

cd $GIT_PATH/
git checkout "v0.2.18"

echo "Applying msgv3_addon.patch"
git apply --reject --whitespace=fix ../msgv3_addon.patch

echo "Applying 0002_zoff_tc___capabilites.diff"
git apply --reject --whitespace=fix ../0002_zoff_tc___capabilites.diff

cd ..

for dir in ${DIRS[@]}; do
    echo "Copying files from $GIT_PATH/$dir to $OUTPUT/$dir"
    cp -rv $GIT_PATH/$dir $OUTPUT
done

cd $GIT_PATH/
echo "cleanup"
git checkout toxcore/*
cd ..

echo "Changing all .c files to .m files (making Xcode happy)"
for file in toxcore/**/*.c; do
    mv -v "$file" "${file%.c}.m"
done

for file in toxcore/toxcore/events/*.c; do
    mv -v "$file" "${file%.c}.m"
done

remove_files_matching() {
    for file in $1; do
        echo "Removing $file"
        rm $file
    done
}

remove_files_matching "toxcore/**/*.bazel"
remove_files_matching "toxcore/**/*_test.cpp"
remove_files_matching "toxcore/**/*_test.cc"
remove_files_matching "toxcore/**/*.api.h"

echo "patching toxcore includes ..."
cd toxcore/
grep -rl '#include <sodium.h>' | grep -v 'install-tox.sh' | xargs -L1 sed -i -e 's_#include <sodium.h>_#include "sodium.h"_'
grep -rl '#include <opus.h>' | grep -v 'install-tox.sh' | xargs -L1 sed -i -e 's_#include <opus.h>_#include "opus.h"_'
grep -rl '#include "../third_party/cmp/cmp.h"' | grep -v 'install-tox.sh' | xargs -L1 sed -i -e 'sx#include "../third_party/cmp/cmp.h"x#include "cmp.h"x'
cd ..
