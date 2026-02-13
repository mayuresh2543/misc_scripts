#!/usr/bin/env bash
#
# 🪨 Stone Kernel Build Script — Modular & Styled
# Original: @enamulhasanabid — Revamped by @mayuresh2543

set -euo pipefail

# ─────────────── 🎨 COLOR CODES ───────────────
RED='\e[1;31m'; GREEN='\e[1;32m'; YELLOW='\e[1;33m'; BLUE='\e[1;34m'; GRAY='\e[1;30m'; BOLD='\e[1m'; RESET='\e[0m'

# ─────────────── 📢 LOGGING HELPERS ───────────────
info()  { echo -e "${BLUE}[INFO]${RESET}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }

start_stage() { STAGE_START=$(date +%s); }
stage_time() { echo -e " ${GRAY}($(($(date +%s) - STAGE_START))s)${RESET}"; }
block_start() { echo -e "\n${GREEN}${BOLD}🔷 $*${RESET}"; echo -e "${GRAY}────────────────────────────────────────────${RESET}"; }
block_end()   { echo -e "${GRAY}────────────────────────────────────────────${RESET}\n"; }

# ─────────────── ⚠️ NOTICE FOR NON-ROOT USERS ───────────────
if (( EUID != 0 )); then
  warn "To automatically install missing packages, run this script with sudo."
fi

# ─────────────── ⚙️ DEFAULT CONFIGURATION ───────────────
SCRIPT_DIR="$(pwd)"
OUTPUT_DIR="$SCRIPT_DIR/out"
CLANG_DIR="$SCRIPT_DIR/clang"
ANYKERNEL_DIR="$SCRIPT_DIR/AnyKernel3"
ZIP_NAME="Vertex-stone-$(date +%Y%m%d-%H%M).zip"

CLANG_REPO="greenforce-project/greenforce_clang"
CLANG_BRANCH="main"

ANYKERNEL3_GIT="https://github.com/mayuresh2543/AnyKernel3.git"
ANYKERNEL3_BRANCH="stone"

export KBUILD_BUILD_USER="android-build"
export KBUILD_BUILD_HOST="localhost"
export SOURCE_DATE_EPOCH=$(date +%s)
export BUILD_REPRODUCIBLE=1

TOTAL_CORES=$(nproc)
DEFAULT_JOBS=$(( TOTAL_CORES > 1 ? (TOTAL_CORES * 8 / 10) : 1 ))
JOBS="$DEFAULT_JOBS"
START_TIME=$(date +%s)

# ─────────────── 🧑‍💻 USER INPUT ───────────────
read_input() {
  block_start "🧑‍💻 USER INPUT"
  echo -e "${BOLD}🛠️  Stone Kernel Build Configuration${RESET}\n"

  read -rp "Kernel repository URL: " KERNEL_REPO
  [[ -z "$KERNEL_REPO" ]] && error "Kernel repo URL is required."

  read -rp "Kernel branch (e.g., 15.0): " KERNEL_BRANCH
  [[ -z "$KERNEL_BRANCH" ]] && error "Kernel branch is required."

  read -rp "Kernel directory name (e.g., my_kernel): " KERNEL_DIR_NAME
  [[ -z "$KERNEL_DIR_NAME" ]] && error "Kernel directory name is required."

  read -rp "Kernel defconfig name (e.g., stone): " DEFCONFIG
  [[ -z "$DEFCONFIG" ]] && error "Defconfig is required."
  [[ "$DEFCONFIG" == *"_defconfig" ]] || DEFCONFIG="${DEFCONFIG}_defconfig"

  echo ""
  echo "Detected $TOTAL_CORES threads on this system."
  echo "Default threads for compilation: $DEFAULT_JOBS (80% of total)"
  read -rp "Enter number of threads to use [default: $DEFAULT_JOBS]: " USER_JOBS
  if [[ "$USER_JOBS" =~ ^[0-9]+$ ]] && (( USER_JOBS >= 1 )); then
    JOBS="$USER_JOBS"
  fi

  KERNEL_DIR="$SCRIPT_DIR/$KERNEL_DIR_NAME"
  block_end
}

# ─────────────── 📦 DEPENDENCY INSTALL ───────────────
install_deps() {
  if (( EUID != 0 )); then
    warn "Skipping dependency check: Not running as root or with sudo."
    return
  fi

  block_start "📦 DEPENDENCY CHECK"
  info "Checking required dependencies..."
  [ -f /etc/os-release ] || error "Cannot detect Linux distro."
  . /etc/os-release

  MISSING=()

  case "$ID" in
    debian|ubuntu)
      PKGS=(git curl tar unzip make zip bc flex bison libssl-dev libelf-dev libncurses-dev rsync python3 lz4 pigz wget)
      for p in "${PKGS[@]}"; do dpkg -s "$p" &>/dev/null || MISSING+=("$p"); done ;;
    fedora|rhel|centos)
      PKGS=(git curl tar unzip make zip bc flex bison openssl-devel openssl-devel-engine elfutils-libelf-devel ncurses-devel rsync python3 lz4 pigz wget)
      for p in "${PKGS[@]}"; do rpm -q "$p" &>/dev/null || MISSING+=("$p"); done ;;
    arch)
      PKGS=(git curl tar unzip make zip bc flex bison openssl elfutils ncurses rsync python lz4 pigz wget)
      for p in "${PKGS[@]}"; do pacman -Qi "$p" &>/dev/null || MISSING+=("$p"); done ;;
    *) error "Unsupported distro: $ID" ;;
  esac

  if (( ${#MISSING[@]} > 0 )); then
    info "Installing missing packages: ${MISSING[*]}"
    case "$ID" in
      debian|ubuntu)      apt update && apt install -y "${MISSING[@]}" ;;
      fedora|rhel|centos) dnf install -y "${MISSING[@]}" @development-tools ;;
      arch)               pacman -Syu --noconfirm "${MISSING[@]}" ;;
    esac
  else
    info "All dependencies are already satisfied."
  fi
  block_end
}

# ─────────────── 📋 BUILD OVERVIEW ───────────────
show_summary() {
  block_start "📋 BUILD OVERVIEW"
  info "Kernel Repository : $KERNEL_REPO"
  info "Kernel Branch     : $KERNEL_BRANCH"
  info "Kernel Directory  : $KERNEL_DIR"
  info "Defconfig         : $DEFCONFIG"
  info "Clang Repo        : $CLANG_REPO"
  info "Clang Branch      : $CLANG_BRANCH"
  info "Clang Directory   : $CLANG_DIR"
  info "AnyKernel3 Repo   : $ANYKERNEL3_GIT"
  info "AnyKernel3 Branch : $ANYKERNEL3_BRANCH"
  info "AnyKernel3 Dir    : $ANYKERNEL_DIR"
  info "Output Directory  : $OUTPUT_DIR"
  info "ZIP Output Name   : $ZIP_NAME"
  info "Build User/Host   : $KBUILD_BUILD_USER@$KBUILD_BUILD_HOST"
  info "Cores Used        : $JOBS / $TOTAL_CORES"
  block_end

  read -rp "🚀 Proceed with build? (y/N): " ans
  [[ "$ans" =~ ^[Yy]$ ]] || error "Build cancelled."
}

# ─────────────── 🧪 BUILD PROCESS ───────────────
build_kernel() {
  block_start "🧪 KERNEL BUILD PROCESS"
  rm -rf "$OUTPUT_DIR" "$ANYKERNEL_DIR"
  mkdir -p "$OUTPUT_DIR"

  start_stage; info "📥 Downloading Clang toolchain..."
  mkdir -p "$CLANG_DIR"
  cd "$CLANG_DIR"
  
  wget -q https://raw.githubusercontent.com/$CLANG_REPO/$CLANG_BRANCH/get_latest_url.sh
  [ -f "get_latest_url.sh" ] || error "Failed to download get_latest_url.sh"
  source get_latest_url.sh; rm -rf get_latest_url.sh
  [ -z "$LATEST_URL" ] && error "LATEST_URL not set by script."
  
  info "Downloading Clang from $LATEST_URL"
  wget -q $LATEST_URL -O "Clang.tar.gz"
  [ -f "Clang.tar.gz" ] || error "Failed to download Clang tarball."
  
  tar -xf Clang.tar.gz
  rm -f Clang.tar.gz
  
  cd "$SCRIPT_DIR"
  
  export PATH="$CLANG_DIR/bin:$PATH"
  for b in clang ld.lld llvm-ar llvm-nm llvm-strip llvm-objcopy llvm-objdump; do
    [ -x "$CLANG_DIR/bin/$b" ] || error "$b not found in Clang toolchain ($CLANG_DIR/bin/$b)."
  done
  info "Toolchain ready"$(stage_time); block_end

  block_start "📥 CLONE KERNEL SOURCE"
  start_stage
  if [ -d "$KERNEL_DIR" ]; then
    warn "Kernel directory '$KERNEL_DIR' already exists. Removing to avoid conflicts."
    rm -rf "$KERNEL_DIR"
  fi
  git clone --depth=1 -b "$KERNEL_BRANCH" "$KERNEL_REPO" "$KERNEL_DIR"
  info "Kernel source ready"$(stage_time); block_end

  block_start "📥 CLONE ANYKERNEL3"
  start_stage
  git clone --depth=1 "$ANYKERNEL3_GIT" -b "$ANYKERNEL3_BRANCH" "$ANYKERNEL_DIR"
  info "AnyKernel3 ready"$(stage_time); block_end

  block_start "🧵 KERNEL COMPILATION"
  start_stage
  cd "$KERNEL_DIR"
  export ARCH=arm64 SUBARCH=arm64 LLVM=1 LLVM_IAS=1 \
         CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm STRIP=llvm-strip \
         OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump \
         CLANG_TRIPLE="aarch64-linux-gnu-" CROSS_COMPILE="aarch64-linux-gnu-"

  make O="$OUTPUT_DIR" distclean mrproper
  make O="$OUTPUT_DIR" "$DEFCONFIG"
  make O="$OUTPUT_DIR" -j"$JOBS" LOCALVERSION= KBUILD_BUILD_USER="$KBUILD_BUILD_USER" KBUILD_BUILD_HOST="$KBUILD_BUILD_HOST"

  IMAGE="$OUTPUT_DIR/arch/arm64/boot/Image"
  [ -f "$IMAGE" ] || error "Kernel image not found."
  info "Kernel compiled"$(stage_time); block_end

  block_start "📦 CREATE FLASHABLE ZIP"
  start_stage
  
  [ -f "$IMAGE" ] || error "Kernel Image not found after build (path: $IMAGE)"
  cp "$IMAGE" "$ANYKERNEL_DIR"/

  cd "$ANYKERNEL_DIR"
  zip -r9 "../$ZIP_NAME" * -x '*.git*' '*.md' '*.placeholder'
  info "ZIP packaged"$(stage_time); block_end

  block_start "🏁 COMPLETION"
  BUILD_DURATION=$(( $(date +%s) - START_TIME ))
  echo -e "${GREEN}${BOLD}🎉 Build Completed Successfully!${RESET}"
  echo -e "${GRAY}────────────────────────────────────────────${RESET}"
  echo -e "📦 ${BOLD}Flashable ZIP   ${RESET}: $ZIP_NAME"
  echo -e "📁 ${BOLD}Location        ${RESET}: $SCRIPT_DIR/$ZIP_NAME"
  echo -e "⚙️  ${BOLD}Cores Utilized  ${RESET}: $JOBS"
  echo -e "⏱️  ${BOLD}Build Duration  ${RESET}: ${BUILD_DURATION}s"
  echo -e "${GRAY}────────────────────────────────────────────${RESET}\n"
}

# ─────────────── 🚀 MAIN ───────────────
read_input
install_deps
show_summary
build_kernel