#!/bin/bash

set -exuo pipefail

# Remove code signatures from osx-64 binaries as they will be invalidated in the later process.
if [[ "${target_platform}" == "osx-64" ]]; then
  for b in `ls bin`; do
    codesign --remove-signature bin/$b
  done
  for b in `ls lib/*.dylib lib/*.dylib.* lib/**/*.dylib`; do
    codesign --remove-signature $b
  done
  codesign --remove-signature lib/jspawnhelper
fi

function jdk_install
{
  chmod +x bin/*
  mkdir -p $PREFIX/bin
  mv bin/* $PREFIX/bin/
  ls -la $PREFIX/bin

  mkdir -p $PREFIX/include
  mv include/* $PREFIX/include
  if [ -e ./lib/jspawnhelper ]; then
    chmod +x ./lib/jspawnhelper
  fi

  mkdir -p $PREFIX/lib
  mv lib/* $PREFIX/lib

  if [ -f "DISCLAIMER" ]; then
    mv DISCLAIMER $PREFIX/DISCLAIMER
  fi

  mkdir -p $PREFIX/conf
  mv conf/* $PREFIX/conf

  mkdir -p $PREFIX/jmods
  mv jmods/* $PREFIX/jmods

  mkdir -p $PREFIX/legal
  mv legal/* $PREFIX/legal

  mkdir -p $PREFIX/man/man1
  mv man/man1/* $PREFIX/man/man1
  rm -rf man/man1
  mv man/* $PREFIX/man
}

chmod +x configure

function double_build
{

  if [[ "$target_platform" == linux* ]]; then
    if [[ -f $PREFIX/include/iconv.h ]]; then
      rm $PREFIX/include/iconv.h
    fi
  fi


  if [[ "${CONDA_BUILD_CROSS_COMPILATION:-0}" == 1 ]]; then
    (
      if [[ "$build_platform" == linux* ]]; then
        if [[ -f $PREFIX/include/iconv.h ]]; then
          rm $PREFIX/include/iconv.h
        fi
      fi

      export CPATH=$BUILD_PREFIX/include
      export LIBRARY_PATH=$BUILD_PREFIX/lib
      export CC=${CC_FOR_BUILD}
      export CXX=${CXX_FOR_BUILD}
      export CPP=${CXX_FOR_BUILD//+/p}
      export NM=$($CC_FOR_BUILD -print-prog-name=nm)
      export AR=$($CC_FOR_BUILD -print-prog-name=ar)
      export OBJCOPY=$($CC_FOR_BUILD -print-prog-name=objcopy)
      export STRIP=$($CC_FOR_BUILD -print-prog-name=strip)
      export PKG_CONFIG_PATH=${BUILD_PREFIX}/lib/pkgconfig

      # CFLAGS and CXXFLAGS are intentionally empty
      export -n CFLAGS
      export -n CXXFLAGS
      unset CPPFLAGS

      unset CFLAGS
      unset CXXFLAGS
      unset LDFLAGS

      ulimit -c unlimited
      mkdir source_build
        pushd source_build
        ../configure \
          --prefix=${PREFIX} \
          --build=${BUILD} \
          --host=${BUILD} \
          --target=${BUILD} \
          --with-extra-cflags="${CDA_CFLAGS}" \
          --with-extra-cxxflags="${CDA_CXXFLAGS} -fpermissive" \
          --with-extra-ldflags="${CDA_LDFLAGS} -lrt" \
          --with-stdc++lib=dynamic \
          --disable-warnings-as-errors \
          --with-x=${PREFIX} \
          --with-cups=${PREFIX} \
          --with-freetype=system \
          --with-giflib=system \
          --with-libpng=system \
          --with-zlib=system \
          --with-lcms=system \
          --with-fontconfig=${PREFIX} \
          --with-boot-jdk=$SRC_DIR/bootstrap
        make JOBS=$CPU_COUNT
        make JOBS=$CPU_COUNT images
      popd
    )
  fi

}

if [[ "$target_platform" == linux* ]]; then 
  if [[ "${CONDA_BUILD_CROSS_COMPILATION:-0}" == 1 ]]; then
    double_build
  fi
fi

export BOOTSTRAP=$SRC_DIR/bootstrap
export CFLAGS_FROM_CONDA=$(echo $CFLAGS | sed 's/-mcpu=[a-z0-9]*//g' | sed 's/-mtune=[a-z0-9]*//g' | sed 's/-march=[a-z0-9]*//g')
export CXXFLAGS_FROM_CONDA=$(echo $CXXFLAGS | sed 's/-mcpu=[a-z0-9]*//g' | sed 's/-mtune=[a-z0-9]*//g' | sed 's/-march=[a-z0-9]*//g')
export LDFLAGS_FROM_CONDA=$LDFLAGS
export CPATH=$PREFIX/include
export LIBRARY_PATH=$PREFIX/lib
export BUILD_CC=${CC_FOR_BUILD}
export BUILD_CXX=${CXX_FOR_BUILD}
export BUILD_CPP=${CXX_FOR_BUILD//+/p}
export BUILD_NM=$($CC_FOR_BUILD -print-prog-name=nm)
export BUILD_AR=$($CC_FOR_BUILD -print-prog-name=ar)
export BUILD_OBJCOPY=$($CC_FOR_BUILD -print-prog-name=objcopy)
export BUILD_STRIP=$($CC_FOR_BUILD -print-prog-name=strip)

export -n CFLAGS
export -n CXXFLAGS
export -n LDFLAGS
export -n MAKEFLAGS

CONFIGURE_ARGS=""
if [[ "${CONDA_BUILD_CROSS_COMPILATION:-0}" == 1 ]]; then
  CONFIGURE_ARGS="--with-build-jdk=$SRC_DIR/source_build/images/jdk"
fi

if [[ "${target_platform}" == osx* ]]; then
  export BOOTSTRAP=$BOOTSTRAP/Contents/Home
  export DSTROOT=$PREFIX
fi

./configure \
  --prefix=$PREFIX \
  --openjdk-target=$BUILD \
  --with-extra-cflags="$CFLAGS_FROM_CONDA" \
  --with-extra-cxxflags="$CXXFLAGS_FROM_CONDA -fpermissive" \
  --with-extra-ldflags="$LDFLAGS_FROM_CONDA" \
  --with-x=$SRC_DIR \
  --with-cups=$PREFIX \
  --with-freetype=bundled \
  --with-fontconfig=$SRC_DIR \
  --with-giflib=bundled \
  --with-libpng=system \
  --with-zlib=system \
  --with-lcms=system \
  --with-stdc++lib=dynamic \
  --disable-warnings-as-errors \
  --with-boot-jdk=$BOOTSTRAP \
  ${CONFIGURE_ARGS}

make JOBS=$CPU_COUNT
make JOBS=$CPU_COUNT images
make install

if [[ "$target_platform" == linux* ]]; then
  # Include dejavu fonts to allow java to work even on minimal cloud
  # images where these fonts are missing (thanks to @chapmanb)
  mkdir -p $PREFIX/lib/fonts
  mv $SRC_DIR/fonts/ttf/* $PREFIX/lib/fonts/
fi
find $PREFIX -name "*.debuginfo" -exec rm -rf {} \;


# Copy the [de]activate scripts to $PREFIX/etc/conda/[de]activate.d.
# This will allow them to be run on environment activation.
for CHANGE in "activate" "deactivate"
do
    mkdir -p "${PREFIX}/etc/conda/${CHANGE}.d"
    cp "${RECIPE_DIR}/scripts/${CHANGE}.sh" "${PREFIX}/etc/conda/${CHANGE}.d/${PKG_NAME}_${CHANGE}.sh"
done
