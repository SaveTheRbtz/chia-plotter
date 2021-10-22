#!/bin/bash

set -xe

export MALLOC_CONF=background_thread:true,metadata_thp:auto,dirty_decay_ms:30000,muzzy_decay_ms:30000 

BASE=/home/rbtz/porn/chia-plotter
for arch in haswell broadwell; do
    cd $BASE
    for d in final tmp1 tmp2; do
        rm -rf ./$d
        mkdir ./$d
    done

    DIR1=$BASE/build1-$arch
    rm -rf $DIR1
    mkdir -p $DIR1
    cd $DIR1

    C_COMMON="-O3 -g -march=$arch"
    cmake -DCMAKE_VERBOSE_MAKEFILE:BOOL=ON -DCMAKE_POSITION_INDEPENDENT_CODE=FALSE -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ -DCMAKE_TOOLCHAIN_PREFIX=llvm- -DBUILD_BLS_PYTHON_BINDINGS=false -DBUILD_BLS_TESTS=false -DBUILD_BLS_BENCHMARKS=false -Dsodium_USE_STATIC_LIBS=ON -DCMAKE_CXX_FLAGS="${C_COMMON}" -DCMAKE_C_FLAGS="${C_COMMON}" -DARITH="gmp"  -DSTLIB=on -DSHLIB=on ..

    make -j8 chia_plot

    perf record -F99 -b -o ${DIR1}/perf.data -- ${DIR1}/chia_plot -d ../final/ -t ../tmp1/ -2 ../tmp2/ -f b5413da029c51777daccf9d7b7e751517a323fe5b3620a1854aef185e94473833268b18b21868193dfc9a9401ae5d87b -c xch1atw03wsw8em3kf29xelsh4msk4g3732u63yv6tdgt355p8707y4sd4aewx -r 8

    create_llvm_prof --profile=${DIR1}/perf.data --binary=${DIR1}/chia_plot --out=${DIR1}/code.prof

    cd $BASE
    DIR2=$BASE/build2-$arch
    rm -rf $DIR2
    mkdir -p $DIR2
    cd $DIR2

    C_COMMON="-O3 -g -march=$arch -gline-tables-only -fprofile-sample-use=$DIR1/code.prof"
    cmake -DCMAKE_VERBOSE_MAKEFILE:BOOL=ON -DCMAKE_POSITION_INDEPENDENT_CODE=FALSE -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ -DCMAKE_TOOLCHAIN_PREFIX=llvm- -DBUILD_BLS_PYTHON_BINDINGS=false -DBUILD_BLS_TESTS=false -DBUILD_BLS_BENCHMARKS=false -Dsodium_USE_STATIC_LIBS=ON -DCMAKE_CXX_FLAGS="${C_COMMON}" -DCMAKE_C_FLAGS="${C_COMMON}" -DARITH="gmp"  -DSTLIB=on -DSHLIB=on ..

    make -j8 chia_plot

    perf record -F99 -b -e cycles:u -o ${DIR2}/perf.data -- ${DIR2}/chia_plot -d ../final/ -t ../tmp1/ -2 ../tmp2/ -f b5413da029c51777daccf9d7b7e751517a323fe5b3620a1854aef185e94473833268b18b21868193dfc9a9401ae5d87b -c xch1atw03wsw8em3kf29xelsh4msk4g3732u63yv6tdgt355p8707y4sd4aewx -r 8


    /home/rbtz/porn/llvm-bolt-build/bin/perf2bolt -p ${DIR2}/perf.data -o ${DIR2}/perf.fdata ${DIR2}/chia_plot || :
    /home/rbtz/porn/llvm-bolt-build/bin/llvm-bolt ${DIR2}/chia_plot -o ${DIR2}/chia_plot.bolt -data=${DIR2}/perf.fdata -reorder-blocks=cache+ -reorder-functions=hfsort -split-functions=2 -split-all-cold -split-eh -dyno-stats -plt=hot --icf --icp-eliminate-loads --frame-opt=hot --indirect-call-promotion=all -update-debug-sections --peepholes=all || :
done
