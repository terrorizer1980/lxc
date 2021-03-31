#!/bin/bash

set -ex

export SANITIZER=${SANITIZER:-address}
flags="-O1 -fno-omit-frame-pointer -gline-tables-only -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION"
coverage_flags="-fsanitize=fuzzer-no-link"

sanitizer_flags="-fsanitize=address -fsanitize-address-use-after-scope"
if [[ "$SANITIZER" == "undefined" ]]; then
    sanitizer_flags="-fsanitize=undefined"
elif [[ "$SANITIZER" == "memory" ]]; then
    sanitizer_flags="-fsanitize=memory -fsanitize-memory-track-origins"
fi

export CC=${CC:-clang}
export CFLAGS=${CFLAGS:-$flags $sanitizer_flags $coverage_flags}

export CXX=${CXX:-clang++}
export CXXFLAGS=${CXXFLAGS:-$flags $sanitizer_flags $coverage_flags}

export OUT=${OUT:-$(pwd)/out}
mkdir -p $OUT

export LIB_FUZZING_ENGINE=${LIB_FUZZING_ENGINE:--fsanitize=fuzzer}

# AFL++ and hoggfuzz are both incompatible with lto=thin apparently
sed -i '/-flto=thin/d' configure.ac

# turn off the libutil dependency
sed -i 's/^AC_CHECK_LIB(util/#/' configure.ac

./autogen.sh
./configure \
    --disable-tools \
    --disable-commands \
    --disable-apparmor \
    --disable-openssl \
    --disable-selinux \
    --disable-seccomp \
    --disable-capabilities \
    --disable-no-undefined

make -j$(nproc)

for fuzz_target_source in src/tests/fuzz-lxc*.c; do
    fuzz_target_name=$(basename "$fuzz_target_source" ".c")
    $CC -c -o "$fuzz_target_name.o" $CFLAGS -Isrc -Isrc/lxc "$fuzz_target_source"
    $CXX $CXXFLAGS $LIB_FUZZING_ENGINE "$fuzz_target_name.o" src/lxc/.libs/liblxc.a -o "$OUT/$fuzz_target_name"
done

perl -lne 'if (/config_jump_table\[\]\s*=/../^}/) { /"([^"]+)"/ && print "$1=" }' src/lxc/confile.c >doc/examples/keys.conf
[[ -s doc/examples/keys.conf ]]

perl -lne 'if (/config_jump_table_net\[\]\s*=/../^}/) { /"([^"]+)"/ && print "lxc.net.$1=" }' src/lxc/confile.c >doc/examples/lxc-net-keys.conf
[[ -s doc/examples/lxc-net-keys.conf ]]

zip -r $OUT/fuzz-lxc-config-read_seed_corpus.zip doc/examples

mkdir fuzz-lxc-define-load_seed_corpus
perl -lne '/([^=]+)/ && print "printf $1= >fuzz-lxc-define-load_seed_corpus/$1"' doc/examples/{keys,lxc-net-keys}.conf | bash
zip -r $OUT/fuzz-lxc-define-load_seed_corpus.zip fuzz-lxc-define-load_seed_corpus
