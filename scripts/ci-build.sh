#!/usr/bin/env bash
# ============================================================
# CI 构建脚本 —— 被 .github/workflows/build.yml 调用
# 步骤: 叠加设备树 -> 应用补丁 -> lunch -> 编译 -> 收集产物
# ============================================================
set -euo pipefail

NAME="${1:?用法: ci-build.sh <device-name>}"
REPO_ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")/.." && pwd)}"
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
	git clone --depth=1 -b "$UPSTREAM_REF" "$UPSTREAM_TREE" /tmp/upstream-device-tree || \
		git clone --depth=1 "$UPSTREAM_TREE" /tmp/upstream-device-tree
	# 上游仓库可能是多设备合集, 尝试找到对应子目录
	SRC_DEV=$(find /tmp/upstream-device-tree -maxdepth 3 -type d -name "*${DEVICE_DIR##*/}*" | head -1)
	[ -z "$SRC_DEV" ] && SRC_DEV=$(find /tmp/upstream-device-tree -maxdepth 2 -type d -name "twrp_device_xiaomi_*" | head -1)
	[ -n "$SRC_DEV" ] && cp -a "$SRC_DEV/." "$DEVICE_DIR/" && echo "    已复制上游设备树: $SRC_DEV"
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
# shellcheck disable=SC1091
. build/envsetup.sh
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
