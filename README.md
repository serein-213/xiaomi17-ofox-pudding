# OrangeFox Recovery for Xiaomi 17 (pudding / sm8750 / Android 17)

小米17 的 OrangeFox R11.1 (A16 底座) 移植 —— **FBE 全层解密可用版**

## 成果

| 层 | 目录 | 状态 |
|---|---|---|
| DE | `/data/system_de/0`、`/data/misc` | ✅ 明文 |
| CE | `/data/media/0`、`/sdcard`、`/data/system_ce/0` | ✅ 明文 |
| — | 真实 spblob（**原始位置**，不依赖 DE 分区副本） | ✅ `[SP] src=REAL` |

设备：Xiaomi 17 (pudding) · sm8750 · Android 17 / HyperOS 4.0.26 · 1220x2656 屏幕

## 目录

```
patches/          5 个源码仓库的完整改动 diff（应用方式见下）
device-tree/      设备树关键文件快照（BoardConfig / fstab / 主题 / sepolicy）
docs/             完整修复报告与镜像校验值
project_fixes/    历史补丁归档
```

## 三个解密根因

### ① `TW_USE_FSCRYPT_POLICY := 2` 缺失（编译期）
设备目录策略全为 **v2**，缺此开关时 `fscrypt_policy` 被编译成 **v1 结构体**，与设备策略永不匹配。
配套开关：`TW_INCLUDE_CRYPTO_FBE`、`TW_INCLUDE_FBE_METADATA_DECRYPT`、`BUILD_BROKEN_DUP_RULES`
线索来源：公开参考 `github.com/YuKongA/twrp_device_xiaomi_sm8750_thales`（109★）

### ② 内核 fscrypt 密钥**绑定在挂载实例(superblock)上**
解锁流程安装密钥后，`Setup_Data_Media()` 会**卸载并重挂 /data**，内核密钥随之全部失效，
文件名退回密文。修复：**每次重挂后重装密钥** —— `[0121]` DE 密钥、`[0125]` CE 密钥（后者是 `/data/media/0` 生效的关键）。

### ③ keystore2 启动竞态
metadata 解密可能早于 keystore2 注册，导致 `/data` 挂载失败、需要重启。
`[0126]` 加入服务就绪等待（正确 AIDL 服务名 + 廉价预判 + 墙钟超时）。

## 性能优化（均有实测对比）

| 项目 | 优化前 | 优化后 |
|---|---|---|
| SELinux 拒绝日志 | 1759 条 | **225 条** (-87%) |
| IHealth 服务轮询 | 68 次 | **2 次** (-97%) |
| keystore 等待上限 | 最坏 50 分钟 | **10 秒** |
| 首屏语言 | 英文 | 中文 |

手段：sepolicy `dontaudit`（用基类属性 `data_file_type`/`property_type`，**只免审计不放宽 allow**）、
`TW_USE_LEGACY_BATTERY_SERVICES := true`、`TW_DEFAULT_LANGUAGE := zh_CN`

## UI 适配 1220x2656（圆角 + 居中挖孔）

| 问题 | 根因 | 修复 |
|---|---|---|
| 卡片/头像变形 | 主题 16:9 与屏幕 1:2.18 不符；`<resolution>` 缺 `resizing` 属性导致 scale_w≠scale_h | `<resolution width="1080" height="2351" resizing="1"/>` |
| 导航栏漂移 | 启动时 `OF_SCREEN_H`(默认1920) 覆盖主题 `screen_h` | `OF_SCREEN_H := 2351` |
| 电量/温度被 R 角裁切 | `OF_STATUS_INDENT_*` 默认 20px | `:= 64` |
| 居中时钟被挖孔遮挡 | 挖孔在正中 | **分列时钟**：新增 `tw_time_hh`/`tw_time_mm`，hh 在孔左、mm 在孔右 |
| 封面图底部橙色条 | 图片 1080x1920 铺不满屏幕 | 生成 1220x2656 适配版 |
| 启动图定制不生效 | fstab 缺 `/recovery`+`/boot` 条目 ⇒ 解包拿到空 block device | 补 fstab + `OF_AB_DEVICE_WITH_RECOVERY_PARTITION := 1` |

### 关键教训
TWRP 主题的 `placement x=` 属性**不支持算术式**：`x="%center_x%-78"` 会被 `atoi` 截断成 `540`，
导致元素叠在屏幕正中（即挖孔下方）而表现为"完全消失"。必须使用**预计算的纯数字变量**。

## 应用补丁

```bash
# 在 AOSP/OrangeFox 源码树内（fox_16.0/），逐个仓库应用：
cd system/vold        && git apply ../../patches/system_vold.patch
cd bootable/recovery  && git apply ../../patches/bootable_recovery.patch
cd build/make         && git apply ../../patches/build_make.patch
cd frameworks/native  && git apply ../../patches/frameworks_native.patch
cd system/security    && git apply ../../patches/system_security.patch
```
设备树文件直接覆盖 `device/xiaomi/sm8750_thales/` 下同名文件。

## 构建

```bash
cd fox_16.0
source build/envsetup.sh
lunch twrp_sm8750_thales-userdebug
m recoveryimage -j$(nproc)
```

## 已知限制
1. 刷入新编译的 recovery.img 会覆盖主题重打包的定制（splash/背景图）
2. 定制界面里的 "Set screen size to …" 会改写 `screen_h` 导致导航栏偏移（重启即恢复）
3. 分列时钟的左右偏移可在 `twres/resources/vars.xml` 的 `clock_hh_x`/`clock_mm_x` 调整
