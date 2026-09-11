#!/usr/bin/env bash
# ============================================================
# CI 构建脚本 —— 被 .github/workflows/build.yml 调用
# 步骤: 叠加设备树 -> 应用补丁 -> lunch -> 编译 -> 收集产物
# ============================================================
set -euo pipefail

NAME="${1:?用法: ci-build.sh <device-name>}"
# 仓库根目录: 优先显式传入的 REPO_ROOT, 否则按脚本自身位置推断。
# (注意: 不能默认用 GITHUB_WORKSPACE —— workflow 里仓库被 checkout 到 repo/ 子目录,
#  而 GITHUB_WORKSPACE 指向其父目录, 会导致读不到 devices.yml)
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
if [ ! -f "$REPO_ROOT/devices.yml" ]; then
	echo "::error::在 $REPO_ROOT 下找不到 devices.yml (REPO_ROOT 解析有误)"
	exit 1
fi
SRC_ROOT="${SRC_ROOT:-$REPO_ROOT/fox_16.0}"

# 从 devices.yml 读取该设备配置(不依赖 yq, 用 python 解析)
read_cfg() {
	python3 - "$REPO_ROOT/devices.yml" "$NAME" "$1" <<-'PY'
	import sys, yaml, json
	cfg, name, key = sys.argv[1], sys.argv[2], sys.argv[3]
	if key.startswith("defaults."):
	    print(yaml.safe_load(open(cfg))["defaults"][key.split(".",1)[1]]); sys.exit()
	for d in yaml.safe_load(open(cfg))["devices"]:
	    if d["name"] == name:
	        print(d[key]); sys.exit()
	sys.exit(f"devices.yml 中找不到设备 {name}")
	PY
}

TARGET=$(read_cfg target)
FALLBACK=$(read_cfg fallback)
OUT_PRODUCT=$(read_cfg out_product)
DEVICE_DIR=$(read_cfg device_dir)
UPSTREAM_TREE=$(read_cfg upstream_tree)
UPSTREAM_REF=$(read_cfg upstream_ref)
# 上游仓库里对应设备的子目录名(显式声明; 上游含 pudding/nezha/pandora/popsicle 多台设备,
# 不能靠模糊匹配 —— 会选错设备)
UPSTREAM_SUBDIR=$(read_cfg upstream_subdir 2>/dev/null || echo "")
BUILD_TARGETS=$(read_cfg defaults.build_targets)
BOOTIMG=$(read_cfg defaults.bootimg)

echo "==> 设备: $NAME"
echo "==> 目标: $TARGET (回退 $FALLBACK)"
echo "==> 设备树: $DEVICE_DIR"
echo "==> 源码树: $SRC_ROOT"

cd "$SRC_ROOT"

# ---------- 1. 叠加设备树 ----------
echo "==> 1/5 准备设备树"
mkdir -p "$DEVICE_DIR"
if [ -n "$UPSTREAM_TREE" ]; then
	echo "    从上游克隆设备树: $UPSTREAM_TREE ($UPSTREAM_REF)"
	if ! git clone --depth=1 -b "$UPSTREAM_REF" "$UPSTREAM_TREE" /tmp/upstream-device-tree; then
		echo "::error::克隆上游设备树失败: $UPSTREAM_TREE @ $UPSTREAM_REF"; exit 1
	fi
	# 上游是多设备合集(pudding/nezha/pandora/popsicle), 必须按声明的子目录取 ——
	# 模糊匹配会拿到别的设备(例如回退逻辑曾可能选中 nezha)
	if [ -z "$UPSTREAM_SUBDIR" ]; then
		echo "::error::devices.yml 未声明 upstream_subdir (上游含多台设备, 不能猜)"
		ls /tmp/upstream-device-tree | sed "s/^/    可用: /"
		exit 1
	fi
	SRC_DEV="/tmp/upstream-device-tree/$UPSTREAM_SUBDIR"
	if [ ! -d "$SRC_DEV" ]; then
		echo "::error::上游设备树子目录不存在: $UPSTREAM_SUBDIR"
		ls /tmp/upstream-device-tree | sed "s/^/    可用: /"
		exit 1
	fi
	cp -a "$SRC_DEV/." "$DEVICE_DIR/" && echo "    已复制上游设备树: $SRC_DEV"
fi

# 叠加本仓库的改动文件(覆盖上游同名文件)
echo "    叠加本仓库 device-tree/ 改动"
cp -a "$REPO_ROOT/device-tree/." "$DEVICE_DIR/"

# ---------- 2. 应用源码补丁 ----------
echo "==> 2/5 应用源码补丁"
apply_patch() {
	local repo="$1" patch="$2"
	[ -d "$repo" ] || { echo "    ! 跳过(目录不存在): $repo"; return 0; }
	if git -C "$repo" apply --check "$patch" 2>/dev/null; then
		git -C "$repo" apply "$patch" && echo "    ✓ $(basename "$patch")"
	else
		echo "    ! $(basename "$patch") 无法干净应用(可能已应用或上下文不符)"
	fi
}
apply_patch system/vold        "$REPO_ROOT/patches/system_vold.patch"
apply_patch bootable/recovery  "$REPO_ROOT/patches/bootable_recovery.patch"
apply_patch build/make         "$REPO_ROOT/patches/build_make.patch"
apply_patch frameworks/native  "$REPO_ROOT/patches/frameworks_native.patch"
apply_patch system/security    "$REPO_ROOT/patches/system_security.patch"

# ---------- 3. lunch ----------
echo "==> 3/5 lunch $TARGET"
# AOSP 的 envsetup.sh 会引用 $TOP 等可能未定义的变量, 而本脚本开了 set -u(nounset),
# 直接 source 会报 "TOP: unbound variable" 并退出。这里先补上 TOP, 再临时放宽 nounset。
export TOP="$(pwd)"
set +u
# shellcheck disable=SC1091
. build/envsetup.sh
set -u
if ! lunch "$TARGET" >/dev/null 2>&1; then
	echo "    lunch $TARGET 失败, 回退 $FALLBACK"
	lunch "$FALLBACK"
fi

# ---------- 4. 编译 ----------
echo "==> 4/5 编译: $BUILD_TARGETS"
JOBS="${BUILD_JOBS:-$(nproc)}"
m -j"$JOBS" $BUILD_TARGETS

# ---------- 5. 收集产物 ----------
echo "==> 5/5 收集产物"
OUT_DIR="out/target/product/$OUT_PRODUCT"
mkdir -p "$REPO_ROOT/artifacts"
for f in "$BOOTIMG" vendor_boot.img boot.img; do
	[ -f "$OUT_DIR/$f" ] && cp "$OUT_DIR/$f" "$REPO_ROOT/artifacts/${NAME}_$f" && \
		echo "    ✓ ${NAME}_$f ($(du -h "$OUT_DIR/$f" | cut -f1))"
done

# OrangeFox 生成的卡刷安装包(内含完整 recovery.img, 可在 recovery 里直接刷)
for z in "$OUT_DIR"/OrangeFox-*.zip "$OUT_DIR"/TWRP-*.zip; do
	[ -f "$z" ] || continue
	bn=$(basename "$z")
	cp "$z" "$REPO_ROOT/artifacts/${NAME}_${bn}" && \
		echo "    ✓ ${NAME}_${bn} ($(du -h "$z" | cut -f1))  [卡刷包]"
done
( cd "$REPO_ROOT/artifacts" && sha256sum ./* > SHA256SUMS.txt 2>/dev/null ) || true
ls -la "$REPO_ROOT/artifacts"
echo "==> 完成"
