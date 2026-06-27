#!/usr/bin/env bash
#
# 🪨 Stone Kernel Build Script — Modular & Styled

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

CLANG_REPO="bachnxuan/aosp_clang_mirror"

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

  KERNEL_DIR="$SCRIPT_DIR/$KERNEL_DIR_NAME"
  REUSE_SOURCE=false
  if [ -d "$KERNEL_DIR" ]; then
    read -rp "Directory '$KERNEL_DIR_NAME' already exists. Use currently synced source? [Y/n]: " ans_reuse
    if [[ "$ans_reuse" =~ ^[Nn]$ ]]; then
      REUSE_SOURCE=false
    else
      REUSE_SOURCE=true
    fi
  fi

  REUSE_CLANG=false
  if [ -d "$CLANG_DIR" ]; then
    read -rp "Directory 'clang' already exists. Use currently synced source? [Y/n]: " ans_reuse_clang
    if [[ "$ans_reuse_clang" =~ ^[Nn]$ ]]; then
      REUSE_CLANG=false
    else
      REUSE_CLANG=true
    fi
  fi

  REUSE_ANYKERNEL=false
  if [ -d "$ANYKERNEL_DIR" ]; then
    read -rp "Directory 'AnyKernel3' already exists. Use currently synced source? [Y/n]: " ans_reuse_ak3
    if [[ "$ans_reuse_ak3" =~ ^[Nn]$ ]]; then
      REUSE_ANYKERNEL=false
    else
      REUSE_ANYKERNEL=true
    fi
  fi

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

  read -rp "Do you want to integrate ReSukiSU? [y/N]: " ans_resukisu
  if [[ "$ans_resukisu" =~ ^[Yy]$ ]]; then
    INTEGRATE_RESUKISU=true
    INTEGRATE_KSU=false
    ZIP_NAME="DarkVertex-ReSukiSU-stone-$(date +%Y%m%d-%H%M).zip"
  else
    INTEGRATE_RESUKISU=false
    read -rp "Do you want to integrate standard KernelSU? [y/N]: " ans_ksu
    if [[ "$ans_ksu" =~ ^[Yy]$ ]]; then
      INTEGRATE_KSU=true
      ZIP_NAME="DarkVertex-KSU-stone-$(date +%Y%m%d-%H%M).zip"
    else
      INTEGRATE_KSU=false
      ZIP_NAME="DarkVertex-stone-$(date +%Y%m%d-%H%M).zip"
    fi
  fi

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
  info "Reuse Source      : $REUSE_SOURCE"
  info "Integrate KSU     : $INTEGRATE_KSU"
  info "Defconfig         : $DEFCONFIG"
  info "Clang Repo        : $CLANG_REPO"
  info "Clang Directory   : $CLANG_DIR"
  info "Reuse Clang       : $REUSE_CLANG"
  info "AnyKernel3 Repo   : $ANYKERNEL3_GIT"
  info "AnyKernel3 Branch : $ANYKERNEL3_BRANCH"
  info "AnyKernel3 Dir    : $ANYKERNEL_DIR"
  info "Reuse AnyKernel3  : $REUSE_ANYKERNEL"
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
  rm -rf "$OUTPUT_DIR"
  if [ "$REUSE_ANYKERNEL" != true ]; then
    rm -rf "$ANYKERNEL_DIR"
  fi
  mkdir -p "$OUTPUT_DIR"

  start_stage; info "📥 Downloading Clang toolchain..."
  if [ "$REUSE_CLANG" = true ]; then
    info "Using existing Clang toolchain in '$CLANG_DIR'."
  else
    if [ -d "$CLANG_DIR" ]; then
      warn "Clang directory '$CLANG_DIR' already exists. Removing to avoid conflicts."
      rm -rf "$CLANG_DIR"
    fi
    mkdir -p "$CLANG_DIR"
    cd "$CLANG_DIR"

    LATEST_URL=$(curl -s https://api.github.com/repos/$CLANG_REPO/releases/latest | grep "browser_download_url.*\.tar\.gz" | cut -d '"' -f 4)
    [ -z "$LATEST_URL" ] && error "Failed to fetch LATEST_URL from GitHub API."

    info "Downloading Clang from $LATEST_URL"
    wget -q $LATEST_URL -O "Clang.tar.gz"
    [ -f "Clang.tar.gz" ] || error "Failed to download Clang tarball."

    tar -xf Clang.tar.gz
    rm -f Clang.tar.gz

    cd "$SCRIPT_DIR"
  fi

  export PATH="$CLANG_DIR/bin:$PATH"
  for b in clang ld.lld llvm-ar llvm-nm llvm-strip llvm-objcopy llvm-objdump; do
    [ -x "$CLANG_DIR/bin/$b" ] || error "$b not found in Clang toolchain ($CLANG_DIR/bin/$b)."
  done
  info "Toolchain ready"$(stage_time); block_end

  block_start "📥 CLONE KERNEL SOURCE"
  start_stage
  if [ "$REUSE_SOURCE" = true ]; then
    info "Using existing kernel source in '$KERNEL_DIR'."
  else
    if [ -d "$KERNEL_DIR" ]; then
      warn "Kernel directory '$KERNEL_DIR' already exists. Removing to avoid conflicts."
      rm -rf "$KERNEL_DIR"
    fi
    info "Cloning kernel source..."
    git clone --depth=1 -b "$KERNEL_BRANCH" "$KERNEL_REPO" "$KERNEL_DIR"
  fi
  info "Kernel source ready"$(stage_time); block_end

  if [ "$INTEGRATE_RESUKISU" = true ]; then
    block_start "🛠️ INTEGRATE RESUKISU"
    start_stage
    cd "$KERNEL_DIR"
    if [ -d "KernelSU" ]; then
      info "ReSukiSU appears to be already integrated, skipping setup."
    else
      info "Downloading and running ReSukiSU setup script..."
      curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash -

      info "Applying KernelSU Manual Hooks patch..."
      cat << 'EOF' > ksu_manual_hook.patch
From d21c720f72953f149c4afac7795ac558f23628bb Mon Sep 17 00:00:00 2001
From: Vedraj Gawas <gawasvedraj@gmail.com>
Date: Fri, 15 May 2026 17:03:07 +0000
Subject: [PATCH] ReSukiSU: Manual Hooks

---
 fs/exec.c                              | 12 ++++++++++++
 fs/open.c                              |  9 +++++++++
 fs/stat.c                              | 23 +++++++++++++++++++++++
 kernel/reboot.c                        |  8 ++++++++
 4 files changed, 52 insertions(+)

diff --git a/fs/exec.c b/fs/exec.c
index 910b407d267e..f75b170524e3 100644
--- a/fs/exec.c
+++ b/fs/exec.c
@@ -1920,12 +1920,21 @@ int do_execve_file(struct file *file, void *__argv, void *__envp)
 	return __do_execve_file(AT_FDCWD, NULL, argv, envp, 0, file);
 }
 
+#ifdef CONFIG_KSU_MANUAL_HOOK
+__attribute__((hot))
+extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr,
+				void *argv, void *envp, int *flags);
+#endif
+
 int do_execve(struct filename *filename,
 	const char __user *const __user *__argv,
 	const char __user *const __user *__envp)
 {
 	struct user_arg_ptr argv = { .ptr.native = __argv };
 	struct user_arg_ptr envp = { .ptr.native = __envp };
+#ifdef CONFIG_KSU_MANUAL_HOOK
+	ksu_handle_execveat((int *)AT_FDCWD, &filename, &argv, &envp, 0);
+#endif
 	return do_execveat_common(AT_FDCWD, filename, argv, envp, 0);
 }
 
@@ -1953,6 +1962,9 @@ static int compat_do_execve(struct filename *filename,
 		.is_compat = true,
 		.ptr.compat = __envp,
 	};
+#ifdef CONFIG_KSU_MANUAL_HOOK // 32-bit ksud and 32-on-64 support
+	ksu_handle_execveat((int *)AT_FDCWD, &filename, &argv, &envp, 0);
+#endif
 	return do_execveat_common(AT_FDCWD, filename, argv, envp, 0);
 }
 
diff --git a/fs/open.c b/fs/open.c
index 3f9f5fda8ebf..f9d5adde41da 100644
--- a/fs/open.c
+++ b/fs/open.c
@@ -440,8 +440,17 @@ long do_faccessat(int dfd, const char __user *filename, int mode)
 	return res;
 }
 
+#ifdef CONFIG_KSU_MANUAL_HOOK
+__attribute__((hot))
+extern int ksu_handle_faccessat(int *dfd, const char __user **filename_user,
+				int *mode, int *flags);
+#endif
+
 SYSCALL_DEFINE3(faccessat, int, dfd, const char __user *, filename, int, mode)
 {
+#ifdef CONFIG_KSU_MANUAL_HOOK
+	ksu_handle_faccessat(&dfd, &filename, &mode, NULL);
+#endif
 	return do_faccessat(dfd, filename, mode);
 }
 
diff --git a/fs/stat.c b/fs/stat.c
index 298eb77668a7..97b947d55fbd 100644
--- a/fs/stat.c
+++ b/fs/stat.c
@@ -357,6 +357,17 @@ SYSCALL_DEFINE2(newlstat, const char __user *, filename,
 	return cp_new_stat(&stat, statbuf);
 }
 
+#ifdef CONFIG_KSU_MANUAL_HOOK
+__attribute__((hot))
+extern int ksu_handle_stat(int *dfd, const char __user **filename_user,
+				int *flags);
+
+extern void ksu_handle_newfstat_ret(unsigned int *fd, struct stat __user **statbuf_ptr);
+#if defined(__ARCH_WANT_STAT64) || defined(__ARCH_WANT_COMPAT_STAT64)
+extern void ksu_handle_fstat64_ret(unsigned long *fd, struct stat64 __user **statbuf_ptr); // optional
+#endif
+#endif
+
 #if !defined(__ARCH_WANT_STAT64) || defined(__ARCH_WANT_SYS_NEWFSTATAT)
 SYSCALL_DEFINE4(newfstatat, int, dfd, const char __user *, filename,
 		struct stat __user *, statbuf, int, flag)
@@ -364,6 +375,9 @@ SYSCALL_DEFINE4(newfstatat, int, dfd, const char __user *, filename,
 	struct kstat stat;
 	int error;
 
+#ifdef CONFIG_KSU_MANUAL_HOOK
+	ksu_handle_stat(&dfd, &filename, &flag);
+#endif
 	error = vfs_fstatat(dfd, filename, &stat, flag);
 	if (error)
 		return error;
@@ -379,6 +393,9 @@ SYSCALL_DEFINE2(newfstat, unsigned int, fd, struct stat __user *, statbuf)
 	if (!error)
 		error = cp_new_stat(&stat, statbuf);
 
+#ifdef CONFIG_KSU_MANUAL_HOOK
+	ksu_handle_newfstat_ret(&fd, &statbuf);
+#endif
 	return error;
 }
 #endif
@@ -506,6 +523,9 @@ SYSCALL_DEFINE2(fstat64, unsigned long, fd, struct stat64 __user *, statbuf)
 	if (!error)
 		error = cp_new_stat64(&stat, statbuf);
 
+#ifdef CONFIG_KSU_MANUAL_HOOK // for 32-bit
+	ksu_handle_fstat64_ret(&fd, &statbuf);
+#endif
 	return error;
 }
 
@@ -515,6 +535,9 @@ SYSCALL_DEFINE4(fstatat64, int, dfd, const char __user *, filename,
 	struct kstat stat;
 	int error;
 
+#ifdef CONFIG_KSU_MANUAL_HOOK // 32-bit su
+	ksu_handle_stat(&dfd, &filename, &flag); 
+#endif
 	error = vfs_fstatat(dfd, filename, &stat, flag);
 	if (error)
 		return error;
diff --git a/kernel/reboot.c b/kernel/reboot.c
index 790c2f514a55..8cbc25d60cb8 100644
--- a/kernel/reboot.c
+++ b/kernel/reboot.c
@@ -310,6 +310,11 @@ DEFINE_MUTEX(system_transition_mutex);
  *
  * reboot doesn't sync: do that yourself before calling this.
  */
+
+#ifdef CONFIG_KSU_MANUAL_HOOK
+extern int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd, void __user **arg);
+#endif
+
 SYSCALL_DEFINE4(reboot, int, magic1, int, magic2, unsigned int, cmd,
 		void __user *, arg)
 {
@@ -317,6 +322,9 @@ SYSCALL_DEFINE4(reboot, int, magic1, int, magic2, unsigned int, cmd,
 	char buffer[256];
 	int ret = 0;
 
+#ifdef CONFIG_KSU_MANUAL_HOOK
+	ksu_handle_sys_reboot(magic1, magic2, cmd, &arg);
+#endif
 	/* We only trust the superuser with rebooting the system. */
 	if (!ns_capable(pid_ns->user_ns, CAP_SYS_BOOT))
 		return -EPERM;
EOF
      patch -p1 < ksu_manual_hook.patch
      rm ksu_manual_hook.patch

      info "Enabling KSU configs in $DEFCONFIG..."
      echo "" >> "arch/arm64/configs/$DEFCONFIG"
      echo "CONFIG_KSU_MANUAL_HOOK=y" >> "arch/arm64/configs/$DEFCONFIG"
      echo "CONFIG_TMPFS_XATTR=y" >> "arch/arm64/configs/$DEFCONFIG"
      sed -i 's/CONFIG_LOCALVERSION="\(.*\)"/CONFIG_LOCALVERSION="\1-ReSukiSU"/' "arch/arm64/configs/$DEFCONFIG"
    fi
    info "ReSukiSU integration ready"$(stage_time); block_end
    cd "$SCRIPT_DIR"
  elif [ "$INTEGRATE_KSU" = true ]; then
    block_start "🛠️ INTEGRATE KERNELSU"
    start_stage
    cd "$KERNEL_DIR"
    if [ -d "KernelSU" ]; then
      info "KernelSU appears to be already integrated, skipping setup."
    else
      info "Downloading and running standard KernelSU setup script..."
      curl -LSs "https://raw.githubusercontent.com/backslashxx/KernelSU/master/kernel/setup.sh" | bash -

      info "Applying KernelSU AVC Audit patch..."
      cat << 'EOF' > ksu_avc_audit.patch
From b6248db061232e08ccd13fe049d4b97325e3cdc4 Mon Sep 17 00:00:00 2001
From: mayuresh2543 <mayureshnanal846@gmail.com>
Date: Sat, 27 Jun 2026 12:08:50 +0530
Subject: [PATCH] KernelSU: selinux: avc: Import slow_avc_audit hook

---
 security/selinux/avc.c | 7 +++++++
 1 file changed, 7 insertions(+)

diff --git a/security/selinux/avc.c b/security/selinux/avc.c
index 7e1e6bc881b0..ca123b0ef410 100644
--- a/security/selinux/avc.c
+++ b/security/selinux/avc.c
@@ -753,6 +753,10 @@ static void avc_audit_post_callback(struct audit_buffer *ab, void *a)
 	}
 }
 
+#if defined(CONFIG_KSU) && !defined(CONFIG_KPROBES)
+extern void ksu_slow_avc_audit(u32 *tsid);
+#endif
+
 /* This is the slow part of avc audit with big stack footprint */
 noinline int slow_avc_audit(struct selinux_state *state,
 			    u32 ssid, u32 tsid, u16 tclass,
@@ -765,6 +769,9 @@ noinline int slow_avc_audit(struct selinux_state *state,
 	if (WARN_ON(!tclass || tclass >= ARRAY_SIZE(secclass_map)))
 		return -EINVAL;
 
+#if defined(CONFIG_KSU) && !defined(CONFIG_KPROBES)
+	ksu_slow_avc_audit(&tsid);
+#endif
 	if (!a) {
 		a = &stack_data;
 		a->type = LSM_AUDIT_DATA_NONE;
EOF
      patch -p1 < ksu_avc_audit.patch || warn "Failed to apply AVC Audit patch!"
      rm -f ksu_avc_audit.patch

      info "Enabling KSU configs in $DEFCONFIG..."
      echo "" >> "arch/arm64/configs/$DEFCONFIG"
      echo "CONFIG_KSU_TAMPER_SYSCALL_TABLE=y" >> "arch/arm64/configs/$DEFCONFIG"
      sed -i 's/^CONFIG_CFI_CLANG=.*/# CONFIG_CFI_CLANG is not set/g' "arch/arm64/configs/$DEFCONFIG"
      sed -i 's/^# CONFIG_CFI_CLANG is not set//g' "arch/arm64/configs/$DEFCONFIG"
      echo "CONFIG_CFI_CLANG=n" >> "arch/arm64/configs/$DEFCONFIG"
      sed -i 's/CONFIG_LOCALVERSION="\(.*\)"/CONFIG_LOCALVERSION="\1-KSU"/' "arch/arm64/configs/$DEFCONFIG"
    fi
    info "KernelSU integration ready"$(stage_time); block_end
    cd "$SCRIPT_DIR"
  fi

  block_start "📥 CLONE ANYKERNEL3"
  start_stage
  if [ "$REUSE_ANYKERNEL" = true ]; then
    info "Using existing AnyKernel3 source in '$ANYKERNEL_DIR'."
  else
    git clone --depth=1 "$ANYKERNEL3_GIT" -b "$ANYKERNEL3_BRANCH" "$ANYKERNEL_DIR"
  fi
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
  echo -e "⚙️ ${BOLD}Cores Utilized  ${RESET}: $JOBS"
  echo -e "⏱️ ${BOLD}Build Duration  ${RESET}: ${BUILD_DURATION}s"
  echo -e "${GRAY}────────────────────────────────────────────${RESET}\n"
}

# ─────────────── 🚀 MAIN ───────────────
LOG_FILE="$SCRIPT_DIR/build_$(date +%Y%m%d-%H%M).log"
exec > >(tee -a "$LOG_FILE") 2>&1
info "Logging all script output to: $LOG_FILE"

read_input
install_deps
show_summary
build_kernel
