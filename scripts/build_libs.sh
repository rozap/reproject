#!/usr/bin/env bash
set -euo pipefail

PROJ_VERSION=${PROJ_VERSION:-9.4.1}
GDAL_VERSION=${GDAL_VERSION:-3.9.3}
SQLITE_VERSION=${SQLITE_VERSION:-3470200}
ROOT=$(git rev-parse --show-toplevel)
PREBUILT_DIR=${PREBUILT_DIR:-${ROOT}/prebuilt}
AARCH64_PREBUILT_DIR="${ROOT}/prebuilt-aarch64"
OS=$(uname -s)

echo "==> Building PROJ ${PROJ_VERSION} and GDAL ${GDAL_VERSION}"

# Build native static libs
if [ -f "${PREBUILT_DIR}/lib/libgdal.a" ]; then
  echo "==> Prebuilt libs already exist at ${PREBUILT_DIR}, skipping."
  echo "    Delete ${PREBUILT_DIR} to force a rebuild."
else
  mkdir -p "${PREBUILT_DIR}"

  if [ "$OS" = "Linux" ]; then
    echo "==> Building inside Docker (debian:bookworm-slim)..."
    docker buildx build \
      --progress=plain \
      --build-arg PROJ_VERSION="${PROJ_VERSION}" \
      --build-arg GDAL_VERSION="${GDAL_VERSION}" \
      --build-arg SQLITE_VERSION="${SQLITE_VERSION}" \
      --output "type=local,dest=${PREBUILT_DIR}" \
      -f Dockerfile.build \
      .

  elif [ "$OS" = "Darwin" ]; then
    echo "==> Installing build dependencies via Homebrew..."
    brew install cmake ninja

    BUILD_DIR=$(mktemp -d)
    trap 'rm -rf "$BUILD_DIR"' EXIT

    echo "==> Building SQLite3 ${SQLITE_VERSION}..."
    curl -fL "https://www.sqlite.org/2024/sqlite-autoconf-${SQLITE_VERSION}.tar.gz" | tar xz -C "$BUILD_DIR"
    (cd "$BUILD_DIR/sqlite-autoconf-${SQLITE_VERSION}" && \
      CFLAGS="-fPIC -O2" ./configure --prefix="${PREBUILT_DIR}" --disable-shared --enable-static && \
      make -j"$(sysctl -n hw.logicalcpu)" && make install)
    export PATH="${PREBUILT_DIR}/bin:${PATH}"

    echo "==> Building PROJ ${PROJ_VERSION}..."
    curl -fL "https://download.osgeo.org/proj/proj-${PROJ_VERSION}.tar.gz" | tar xz -C "$BUILD_DIR"
    cmake -S "$BUILD_DIR/proj-${PROJ_VERSION}" -B "$BUILD_DIR/proj-build" -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="${PREBUILT_DIR}" \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DBUILD_SHARED_LIBS=OFF \
      -DBUILD_TESTING=OFF \
      -DBUILD_APPS=OFF \
      -DENABLE_TIFF=OFF \
      -DENABLE_CURL=OFF \
      "-DSQLITE3_INCLUDE_DIR=${PREBUILT_DIR}/include" \
      "-DSQLITE3_LIBRARY=${PREBUILT_DIR}/lib/libsqlite3.a"
    cmake --build "$BUILD_DIR/proj-build" --parallel
    cmake --install "$BUILD_DIR/proj-build"

    echo "==> Building GDAL ${GDAL_VERSION} (minimal OGR build)..."
    curl -fL "https://github.com/OSGeo/gdal/releases/download/v${GDAL_VERSION}/gdal-${GDAL_VERSION}.tar.gz" \
      | tar xz -C "$BUILD_DIR"
    cmake -S "$BUILD_DIR/gdal-${GDAL_VERSION}" -B "$BUILD_DIR/gdal-build" -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="${PREBUILT_DIR}" \
      -DCMAKE_PREFIX_PATH="${PREBUILT_DIR}" \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DBUILD_SHARED_LIBS=OFF \
      -DGDAL_BUILD_OPTIONAL_DRIVERS=OFF \
      -DOGR_BUILD_OPTIONAL_DRIVERS=OFF \
      -DBUILD_APPS=OFF \
      -DBUILD_TESTING=OFF \
      -DGDAL_USE_CURL=OFF \
      -DGDAL_USE_EXPAT=OFF \
      -DGDAL_USE_LIBXML2=OFF \
      -DGDAL_USE_PNG=OFF \
      -DGDAL_USE_JPEG=OFF \
      -DGDAL_USE_TIFF=OFF \
      -DGDAL_USE_JSONC=OFF \
      -DGDAL_USE_QHULL=OFF \
      -DGDAL_USE_OPENJPEG=OFF \
      -DGDAL_USE_WEBP=OFF \
      -DGDAL_USE_GEOS=OFF \
      -DGDAL_OBJECT_LIBRARIES_POSITION_INDEPENDENT_CODE=ON \
      "-DPROJ_INCLUDE_DIR=${PREBUILT_DIR}/include" \
      "-DPROJ_LIBRARY=${PREBUILT_DIR}/lib/libproj.a" \
      "-DSQLITE3_INCLUDE_DIR=${PREBUILT_DIR}/include" \
      "-DSQLITE3_LIBRARY=${PREBUILT_DIR}/lib/libsqlite3.a"
    cmake --build "$BUILD_DIR/gdal-build" --parallel
    cmake --install "$BUILD_DIR/gdal-build"

  else
    echo "Unsupported OS: $OS" >&2
    exit 1
  fi

  echo ""
  echo "==> Done. Static libs installed to ${PREBUILT_DIR}"
fi

# Build aarch64 static libs via Docker with QEMU emulation.
# Skipped in CI — the workflow uses native arm64 runners for aarch64 builds.
if [ "$OS" = "Linux" ] && [ -z "${CI:-}" ]; then
  if [ -f "${AARCH64_PREBUILT_DIR}/lib/libgdal.a" ]; then
    echo "==> aarch64 prebuilt libs already exist at ${AARCH64_PREBUILT_DIR}, skipping."
    echo "    Delete ${AARCH64_PREBUILT_DIR} to force a rebuild."
  else
    echo "==> Building aarch64 static libs via Docker (requires QEMU binfmt)..."
    docker run --rm --privileged tonistiigi/binfmt --install arm64
    mkdir -p "${AARCH64_PREBUILT_DIR}"
    docker buildx build \
      --platform linux/arm64 \
      --progress=plain \
      --build-arg PROJ_VERSION="${PROJ_VERSION}" \
      --build-arg GDAL_VERSION="${GDAL_VERSION}" \
      --build-arg SQLITE_VERSION="${SQLITE_VERSION}" \
      --output "type=local,dest=${AARCH64_PREBUILT_DIR}" \
      -f Dockerfile.build \
      .
  fi
fi

if [ -n "${CI:-}" ]; then
  echo "==> Running in CI — skipping local precompile (handled by workflow)."
  exit 0
fi

CACHE_DIR="${CACHE_DIR:-${ROOT}/cache}"
mkdir -p "${CACHE_DIR}"

echo "==> Precompiling NIF tarball (native)..."
(cd "${ROOT}" && \
  BUNDLED_LIBS_PREFIX="${PREBUILT_DIR}" \
  ELIXIR_MAKE_CACHE_DIR="${CACHE_DIR}" \
  MIX_ENV=prod \
  mix elixir_make.precompile)

if [ "$OS" = "Linux" ]; then
  if command -v aarch64-linux-gnu-g++ >/dev/null 2>&1 && [ -f "${AARCH64_PREBUILT_DIR}/lib/libgdal.a" ]; then
    echo "==> Cross-compiling aarch64-linux-gnu NIF..."
    (cd "${ROOT}" && \
      CC=aarch64-linux-gnu-gcc \
      CXX=aarch64-linux-gnu-g++ \
      BUNDLED_LIBS_PREFIX="${AARCH64_PREBUILT_DIR}" \
      ELIXIR_MAKE_CACHE_DIR="${CACHE_DIR}" \
      CC_PRECOMPILER_CURRENT_TARGET=aarch64-linux-gnu \
      MIX_ENV=prod \
      mix elixir_make.precompile)
  else
    echo "==> Skipping aarch64 NIF cross-compile."
    echo "    Ensure aarch64 libs are built and install cross-compiler:"
    echo "    sudo apt-get install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu"
  fi
fi

echo ""
echo "==> Tarball(s) written to ${CACHE_DIR}:"
ls "${CACHE_DIR}"/*.tar.gz 2>/dev/null || echo "  (none found)"
echo ""
echo "==> To test locally:"
echo "    REPROJECT_BUILD_FROM_SOURCE=1 BUNDLED_LIBS_PREFIX=${PREBUILT_DIR} mix compile"
echo "    mix test"
