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
  # 皮肤完全跟随 R12.0: 上游设备树带的 Night 皮肤是 R11.3 形态(图标定义不全), 删除之
  rm -f "$DEVICE_DIR/recovery/root/twres/themes/styles/Night.xml"                                               

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

# ---------- 2.5 soong Android.mk 允许清单 ----------
# OFOX16 manifest 的 external/magisk-prebuilt/Android.mk 命中 soong 黑名单
# (build/soong/ui/build/androidmk_denylist.go 里 external/ 在前缀列表中),
# 命中即 ctx.Fatalf 直接退出, 表现为 out/soong.log 在
# "Found blocked Android.mk file: external/magisk-prebuilt/Android.mk" 处中断,
# CI 日志里只看到 "failed to build some targets"。
# 本地 build_pudding.sh:189-195 就是把它写进 allowlist 解决的。
echo "==> 2.5/5 写入 soong Android.mk allowlist"
AWDIR="vendor/google/build/androidmk"
mkdir -p "$AWDIR"
if [ -f "$AWDIR/allowlist.txt" ]; then
	grep -qxF 'external/magisk-prebuilt/Android.mk' "$AWDIR/allowlist.txt" || \
		printf 'external/magisk-prebuilt/Android.mk\n' >> "$AWDIR/allowlist.txt"
else
	printf 'external/magisk-prebuilt/Android.mk\n' > "$AWDIR/allowlist.txt"
fi
echo "    ✓ allowlist 内容:"; sed 's/^/      /' "$AWDIR/allowlist.txt"

# ---------- 3. lunch ----------
echo "==> 3/5 lunch $TARGET"
# AOSP 的 envsetup.sh 会引用 $TOP 等可能未定义的变量, 而本脚本开了 set -u(nounset),
# 直接 source 会报 "TOP: unbound variable" 并退出。这里先补上 TOP, 再临时放宽 nounset。
export TOP="$(pwd)"
# 安装包同时接受 sm8850(实际 SoC) 与 sm8750(历史代号), 写入 update-binary 的 TARGET_DEVICE_ALT
export FOX_TARGET_DEVICES="sm8750 pudding"
# envsetup.sh 和 lunch 内部大量引用可能未定义的变量(BUILD_VAR_CACHE_READY 等),
# 全程必须在 nounset 关闭的状态下执行 —— 本地 build_pudding.sh 也是这么做的。
set +u
# lunch 内部走 check_product -> `command make -f build/core/config.mk dump-many-vars`。
# AOSP 树里的 make 可能是包装器(实测报 "Unknown option: -f"), 会让 check_product 失败,
# 从而把 lunch 误报成 "Don't have a product spec"。把系统 GNU make 所在目录提到 PATH 最前。
if MAKE_REAL=$(command -v /usr/bin/make 2>/dev/null) && /usr/bin/make --version 2>/dev/null | grep -q "GNU Make"; then
	export PATH="/usr/bin:$PATH"
	echo "    使用系统 GNU make: $(/usr/bin/make --version | head -1)"
fi
# shellcheck disable=SC1091
. build/envsetup.sh
# release 名(bp2a/ap2a)由 vendor/twrp/vars/aosp_target_release 决定;
# TWRP-A16 上游的 vendor/twrp 未必带此文件(本地那份标注 "Updated manually"),
# 缺失时补写, 否则 lunch 的 release 段解析不出来。
if [ ! -f vendor/twrp/vars/aosp_target_release ]; then
	mkdir -p vendor/twrp/vars
	printf '# Updated by ci-build.sh\naosp_target_release=bp2a\n' > vendor/twrp/vars/aosp_target_release
	echo "    已补写 vendor/twrp/vars/aosp_target_release (bp2a)"
fi
echo "    --- aosp_target_release ---"; cat vendor/twrp/vars/aosp_target_release 2>/dev/null | sed 's/^/      /' || true
# 诊断: 设备树放置与可用 lunch 组合(roomservice 报 "Device X not found" 时靠这些定位)

echo "    --- device/xiaomi/ ---"; ls device/xiaomi/ 2>/dev/null | sed 's/^/      /' || true

echo "    --- $DEVICE_DIR 关键文件 ---"; ls "$DEVICE_DIR"/AndroidProducts.mk "$DEVICE_DIR"/BoardConfig.mk "$DEVICE_DIR"/twrp_*.mk 2>/dev/null | sed 's/^/      /' || true

echo "    --- AndroidProducts.mk ---"; grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$DEVICE_DIR/AndroidProducts.mk" 2>/dev/null | sed 's/^/      /' || true

# 决定性诊断: lunch 内部用 check_product -> make -f build/core/config.mk dump-many-vars
# 浅克隆下若缺依赖, 这里能看到真实报错(而不是只看到 lunch 的 "not found")
echo "    --- DIAG_CHECK_PRODUCT: device 目录实况 ---"
ls -la "$DEVICE_DIR"/ 2>&1 | head -20 | sed 's/^/      /' || true
echo "    --- DIAG_CHECK_PRODUCT: make dump-many-vars 实测 ---"
TMPVARS=$(mktemp)
if /usr/bin/make -f build/core/config.mk dump-many-vars TARGET_PRODUCT="$TARGET" \
	TARGET_BUILD_VARIANT=eng TARGET_RELEASE=bp2a >"$TMPVARS" 2>&1; then
	echo "      ✓ make dump-many-vars 成功"
	grep -E "^(TARGET_PRODUCT|TARGET_DEVICE|TARGET_RELEASE)=" "$TMPVARS" | head -5 | sed 's/^/      /' || true
else
	echo "      ✗ make dump-many-vars 失败(真实原因):"
	tail -20 "$TMPVARS" | sed 's/^/        /'
fi
rm -f "$TMPVARS"

# 第一次 lunch 也保留输出, 否则失败原因被 /dev/null 吞掉

# 注意: 绝不能写成 `lunch ... | tail` ——
#   ① lunch 是 envsetup.sh 里的 bash 函数, 放进管道会在子 shell 执行,
#      它导出的 TARGET_PRODUCT/TARGET_DEVICE/TARGET_BUILD_VARIANT 等全部丢失,
#      后续编译步骤拿不到 lunch 结果;
#   ② 管道退出码取最后一个命令, `if !` 恒为假, 回退分支永远不会执行。
# 这里改为: 输出重定向到文件后本地 tail, lunch 保持在当前 shell 执行。
LUNCH_LOG=/tmp/lunch.log
if lunch "$TARGET" >"$LUNCH_LOG" 2>&1; then
	tail -12 "$LUNCH_LOG" | sed 's/^/      /'
else
	tail -12 "$LUNCH_LOG" | sed 's/^/      /'
	echo "    lunch $TARGET 失败, 回退 $FALLBACK"
	if ! lunch "$FALLBACK" >"$LUNCH_LOG" 2>&1; then
		tail -20 "$LUNCH_LOG" | sed 's/^/      /'
		# 兜底: lunch 依赖 check_product(make dump-many-vars), 浅克隆下可能失败。
		# 直接设置 lunch 会导出的关键变量, 让后续编译仍可进行。
		echo "    尝试兜底: 直接设置 TARGET_* 变量"
		# 产品名 = target 去掉 "-<release>-<variant>" 后缀 (如 twrp_sm8850_thales-bp2a-eng)
		export TARGET_PRODUCT="${TARGET%-*-*}"
		export TARGET_DEVICE="${OUT_PRODUCT:-sm8850_thales}"
		export TARGET_BUILD_VARIANT=eng
		export TARGET_RELEASE=bp2a
		export TARGET_BUILD_TYPE=release
		echo "    TARGET_PRODUCT=$TARGET_PRODUCT TARGET_DEVICE=$TARGET_DEVICE"
		# 校验 product makefile 是否真的提供该产品(而不是检查尚未生成的 out/)
		PMK="$DEVICE_DIR/$(echo "$TARGET" | sed 's/-[^-]*-[^-]*$//').mk"
		if [ -f "$PMK" ] && grep -q "PRODUCT_NAME *:= *$(echo "$TARGET" | sed 's/-[^-]*-[^-]*$//')" "$PMK"; then
			echo "    ✓ 兜底成立: $PMK 提供该产品, 直接进入编译"
		else
			echo "::error::lunch 全部失败且兜底无效 (未找到 $PMK 或其中无 PRODUCT_NAME)"
			ls "$DEVICE_DIR"/twrp_*.mk 2>/dev/null | sed 's/^/      可用: /' || true
			exit 1
		fi
	fi
	tail -12 "$LUNCH_LOG" | sed 's/^/      /'
fi
# lunch 成功后显式固化关键变量, 供后续步骤与子进程使用
export TARGET_PRODUCT TARGET_DEVICE TARGET_BUILD_VARIANT TARGET_RELEASE 2>/dev/null || true
echo "    TARGET_PRODUCT=${TARGET_PRODUCT:-?} TARGET_DEVICE=${TARGET_DEVICE:-?} TARGET_BUILD_VARIANT=${TARGET_BUILD_VARIANT:-?}"

echo "    env: TARGET_PRODUCT=${TARGET_PRODUCT:-} TARGET_DEVICE=${TARGET_DEVICE:-} TARGET_BUILD_VARIANT=${TARGET_BUILD_VARIANT:-}"

# ---------- 4. 编译 ----------
echo "==> 4/5 编译: $BUILD_TARGETS"
# 内存优先: soong_build 在 15.6GB runner 上 OOM, 保守用 2 并行(与本地一致)。
# 可通过 workflow 的 BUILD_JOBS 覆盖。
JOBS="${BUILD_JOBS:-2}"
# 直接用 soong_ui, 不依赖 envsetup.sh 里的 m 函数 ——
# 实测 CI 环境里 m 未解析成函数时会走到 make 调 build/core/config.mk 的守卫,
# 直接 $(error done) 秒退("failed to build some targets (1 seconds)")。
# soong_ui.bash --make-mode 是 AOSP 官方入口, 自己完成产品解析, 不依赖 lunch。
# build/soong/bin/m 是与 mka 等价的真实脚本(envsetup 里的是 bash 函数, 子进程不可用)。
# 本地 build_pudding.sh:220-222 用的就是它, 并注明 "soong_ui 每次启动即 Fatal 退出"。
M_BIN="build/soong/bin/m"
echo "    --- 编译入口探测 ---"
ls -la "$M_BIN" 2>&1 | sed 's/^/      /' || echo "      (build/soong/bin/m 不存在)"
ls -la build/soong/soong_ui.bash 2>&1 | sed 's/^/      /' || true
echo "      M_BIN 可执行: $([ -x "$M_BIN" ] && echo 是 || echo 否)"
if [ -x "$M_BIN" ]; then
	echo "    → 使用 build/soong/bin/m"
	set +e
	env TARGET_PRODUCT="${TARGET_PRODUCT:-twrp_$OUT_PRODUCT}" \
	    TARGET_DEVICE="${TARGET_DEVICE:-$OUT_PRODUCT}" \
	    TARGET_BUILD_VARIANT="${TARGET_BUILD_VARIANT:-eng}" \
	    TARGET_RELEASE="${TARGET_RELEASE:-bp2a}" \
	    TARGET_BUILD_TYPE=release \
	    "$M_BIN" -j"$JOBS" $BUILD_TARGETS
	BUILD_RC=$?
	set -e
	if [ "$BUILD_RC" -ne 0 ]; then
		# _wrap_build 把详细输出写进 out/ 的日志, 只在失败时打一行提示。
		# 这里把真实报错倒出来, 否则 CI 日志里只有 "failed to build some targets"。
		echo "::group::构建失败详情 (rc=$BUILD_RC)"
		for f in out/error.log out/soong.log out/build_error.log; do
			if [ -f "$f" ]; then
				echo "--- $f (尾 80 行) ---"
				tail -80 "$f" | sed 's/^/    /'
			fi
		done
		for g in out/verbose.log.gz out/soong.log.gz; do
			if [ -f "$g" ]; then
				echo "--- $g (尾 120 行) ---"
				zcat "$g" 2>/dev/null | tail -120 | sed 's/^/    /'
			fi
		done
		echo "--- out/ 下的日志清单 ---"
		ls -la out/*.log out/*.gz 2>/dev/null | sed 's/^/    /' || true
		echo "--- 最后一次 ninja 输出(若存在) ---"
		find out -maxdepth 2 -name "*.ninja_log" -o -maxdepth 2 -name "ninja_log" 2>/dev/null | head -3 | sed 's/^/    /'
		echo "::endgroup::"
		exit "$BUILD_RC"
	fi
elif [ -x build/soong/soong_ui.bash ]; then
	echo "    → 回退 soong_ui.bash --make-mode (build/soong/bin/m 不可执行)"
	env TARGET_PRODUCT="${TARGET_PRODUCT:-twrp_$OUT_PRODUCT}" TARGET_DEVICE="${TARGET_DEVICE:-$OUT_PRODUCT}" \
	    TARGET_BUILD_VARIANT="${TARGET_BUILD_VARIANT:-eng}" TARGET_RELEASE="${TARGET_RELEASE:-bp2a}" \
	    build/soong/soong_ui.bash --make-mode -j"$JOBS" $BUILD_TARGETS
else
	echo "::error::找不到 build/soong/bin/m 或 soong_ui.bash"
	exit 1
fi

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
