#
# Copyright 2017 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# This contains the module build definitions for the hardware-specific
# components for this device.
#
# As much as possible, those components should be built unconditionally,
# with device-specific names to avoid collisions, to avoid device-specific
# bitrot and build breakages. Building a component unconditionally does
# *not* include it on all devices, so it is safe even with hardware-specific
# components.

# Runtime evidence in the extracted recovery points at device/xiaomi/sm8850_thales,
# with popsicle-specific product properties injected at build time.
#
# Architecture
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := kryo385

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := $(TARGET_ARCH_VARIANT)
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := $(TARGET_CPU_VARIANT)
TARGET_2ND_CPU_VARIANT_RUNTIME := $(TARGET_CPU_VARIANT_RUNTIME)

ENABLE_CPUSETS := true
ENABLE_SCHEDBOOST := true

# Bootloader
TARGET_BOOTLOADER_BOARD_NAME := sun
TARGET_NO_BOOTLOADER := true
TARGET_USES_UEFI := true

# DTB
ifndef BOARD_PREBUILT_DTBOIMAGE
BOARD_KERNEL_SEPARATED_DTBO := true
endif
TARGET_PREBUILT_DTB := $(DEVICE_PATH)/prebuilt/dtb.img
ifndef TARGET_PREBUILT_DTB
BOARD_INCLUDE_DTB_IN_BOOTIMG := true
else
BOARD_MKBOOTIMG_ARGS += --dtb $(TARGET_PREBUILT_DTB)
endif

# Kernel
TARGET_NO_KERNEL := false
TARGET_KERNEL_ARCH := $(TARGET_ARCH)
BOARD_KERNEL_CMDLINE := \
    androidboot.hardware=qcom \
    androidboot.memcg=1 \
    androidboot.usbcontroller=a600000.dwc3 \
    cgroup.memory=nokmem,nosocket \
    loop.max_part=7 \
    lpm_levels.sleep_disabled=1 \
    msm_rtb.filter=0x237 \
    pcie_ports=compat \
    service_locator.enable=1 \
    swiotlb=0 \
    ip6table_raw.raw_before_defrag=1 \
    iptable_raw.raw_before_defrag=1
BOARD_KERNEL_PAGESIZE := 4096
BOARD_KERNEL_IMAGE_NAME := Image
BOARD_BOOT_HEADER_VERSION := 4
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/Image
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)
BOARD_RAMDISK_USE_LZ4 := true
ifndef TARGET_PREBUILT_KERNEL
TARGET_KERNEL_SOURCE := kernel/xiaomi/sm8750
TARGET_KERNEL_CONFIG := vendor/sun_defconfig
BOARD_VENDOR_RAMDISK_RECOVERY_KERNEL_MODULES_LOAD := msm_drm.ko
BOOT_KERNEL_MODULES := $(BOARD_VENDOR_RAMDISK_RECOVERY_KERNEL_MODULES_LOAD)
else
TARGET_FORCE_PREBUILT_KERNEL := true
BOARD_VENDOR_RAMDISK_KERNEL_MODULES := $(DEVICE_PATH)/prebuilt/dlkm/msm_drm.ko
endif

# Platform
TARGET_BOARD_PLATFORM := xiaomi_sm8750
TARGET_BOARD_PLATFORM_GPU := qcom-adreno830
TARGET_USES_HARDWARE_QCOM_BOOTCTRL := true
QCOM_BOARD_PLATFORMS += $(TARGET_BOARD_PLATFORM)

# Partition Info
BOARD_FLASH_BLOCK_SIZE := 262144 # (BOARD_KERNEL_PAGESIZE * 64)
BOARD_USES_PRODUCTIMAGE := true

BOARD_BOOTIMAGE_PARTITION_SIZE := 100663296
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := $(BOARD_BOOTIMAGE_PARTITION_SIZE)
BOARD_SYSTEMIMAGE_JOURNAL_SIZE := 0
BOARD_SYSTEMIMAGE_EXTFS_INODE_COUNT := 4096
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true

# Dynamic/Logical Partitions
# TODO: replace with lpdump-derived values when imported.
BOARD_SUPER_PARTITION_SIZE := 7516192768
BOARD_SUPER_PARTITION_GROUPS := qti_dynamic_partitions
BOARD_QTI_DYNAMIC_PARTITIONS_SIZE := 7511998464 # BOARD_SUPER_PARTITION_SIZE - 4MB
BOARD_QTI_DYNAMIC_PARTITIONS_PARTITION_LIST := \
    system \
    system_ext \
    product \
    odm \
    vendor \
    vendor_dlkm \
    system_dlkm

# Workaround for error copying vendor files to recovery ramdisk
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDOR_DLKMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_SYSTEM_DLKMIMAGE_FILE_SYSTEM_TYPE := ext4
TARGET_COPY_OUT_PRODUCT := product
TARGET_COPY_OUT_SYSTEM_EXT := system_ext
TARGET_COPY_OUT_VENDOR := vendor
TARGET_COPY_OUT_VENDOR_DLKM := vendor_dlkm
TARGET_COPY_OUT_SYSTEM_DLKM := system_dlkm

# Recovery
ifeq ($(BOARD_BOOT_HEADER_VERSION),3)
BOARD_USES_RECOVERY_AS_BOOT := true
endif
# [真机核查修正] 不使用 vendor_boot 内嵌 recovery; recovery 镜像为 ramdisk-only 刷入 recovery 分区
BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true
BOARD_HAS_LARGE_FILESYSTEM := true
BOARD_HAS_NO_SELECT_BUTTON := true
BOARD_SUPPRESS_SECURE_ERASE := true
# [真机核查修正] 本设备有独立 recovery_a/b 分区 (实测 104857600), recovery 走独立分区
TARGET_RECOVERY_DEVICE_MODULES += \
    libdmabufheap \
    hostfs_tool \
    libion \
    libxml2 \
    vendor.display.config@1.0 \
    vendor.display.config@2.0
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery.fstab

# Use mke2fs to create ext4 images
TARGET_USES_MKE2FS := true

# AVB
BOARD_AVB_ENABLE := true
BOARD_AVB_VBMETA_SYSTEM := system
BOARD_AVB_VBMETA_SYSTEM_KEY_PATH := external/avb/test/data/testkey_rsa2048.pem
BOARD_AVB_VBMETA_SYSTEM_ALGORITHM := SHA256_RSA2048
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX := $(PLATFORM_SECURITY_PATCH_TIMESTAMP)
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX_LOCATION := 1

# Encryption
BOARD_USES_METADATA_PARTITION := true
BOARD_USES_QCOM_FBE_DECRYPTION := true
PLATFORM_VERSION := 99.87.36
PLATFORM_VERSION_LAST_STABLE := $(PLATFORM_VERSION)

# Extras
BOARD_ROOT_EXTRA_FOLDERS := batinfo
TARGET_SYSTEM_PROP += $(DEVICE_PATH)/system.prop
TARGET_VENDOR_PROP += $(DEVICE_PATH)/vendor.prop

# TWRP specific build flags
TARGET_RECOVERY_QCOM_RTC_FIX := true
TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888
TARGET_USE_CUSTOM_LUN_FILE_PATH := /config/usb_gadget/g1/functions/mass_storage.0/lun.%d/file
TW_CUSTOM_CPU_TEMP_PATH := "/sys/devices/virtual/thermal/thermal_zone50/temp"
TW_THEME := portrait_hdpi
TW_BRIGHTNESS_PATH := "/sys/class/backlight/panel0-backlight/brightness"
TW_QCOM_ATS_OFFSET := 1621580431500
TW_DEFAULT_BRIGHTNESS := 820
TW_MAX_BRIGHTNESS := 1024
TW_EXCLUDE_DEFAULT_USB_INIT := true
TW_EXTRA_LANGUAGES := true
TW_INCLUDE_CRYPTO := true
TW_NO_EXFAT_FUSE := true
TW_NO_HAPTICS := true
TW_NO_SCREEN_BLANK := true
TW_INCLUDE_REPACKTOOLS := true
TW_INCLUDE_RESETPROP := true
TW_OVERRIDE_PROPS_ADDITIONAL_PARTITIONS := odm
TW_OVERRIDE_SYSTEM_PROPS := \
    "ro.build.date.utc;ro.bootimage.build.date.utc=ro.build.date.utc;ro.odm.build.date.utc=ro.build.date.utc;ro.product.build.date.utc=ro.build.date.utc;ro.system.build.date.utc=ro.build.date.utc;ro.system_ext.build.date.utc=ro.build.date.utc;ro.vendor.build.date.utc=ro.build.date.utc;ro.build.product=ro.product.device;ro.build.fingerprint=ro.bootimage.build.fingerprint;ro.build.version.incremental=ro.bootimage.build.version.incremental;ro.product.odm.device;ro.vendor.product.device.oem;ro.vendor.product.device.oem;ro.product.device=ro.vendor.product.device.oem"
RECOVERY_LIBRARY_SOURCE_FILES += \
    $(TARGET_OUT_SHARED_LIBRARIES)/libdmabufheap.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/libion.so \
    $(TARGET_OUT_SHARED_LIBRARIES)/libxml2.so \
    $(TARGET_OUT_SYSTEM_EXT_SHARED_LIBRARIES)/vendor.display.config@1.0.so \
    $(TARGET_OUT_SYSTEM_EXT_SHARED_LIBRARIES)/vendor.display.config@2.0.so
TW_LOAD_VENDOR_MODULES := "q6_pdr_dlkm.ko q6_notifier_dlkm.ko snd_event_dlkm.ko apr_dlkm.ko adsp_loader_dlkm.ko synaptics_tcm2.ko nxp-nci.ko stm_st54se_gpio.ko stm_nfc_i2c.ko qcom-hv-haptics.ko cs40l26-i2c.ko"
TW_LOAD_VENDOR_MODULES_EXCLUDE_GKI := true
TW_LOAD_PREBUILT_MODULES_AT_FIRST := true
# TWRP Debug Flags
#TWRP_EVENT_LOGGING := true
TARGET_USES_LOGD := true
TWRP_INCLUDE_LOGCAT := true
TARGET_RECOVERY_DEVICE_MODULES += debuggerd
RECOVERY_BINARY_SOURCE_FILES += $(TARGET_OUT_EXECUTABLES)/debuggerd
TARGET_RECOVERY_DEVICE_MODULES += strace
RECOVERY_BINARY_SOURCE_FILES += $(TARGET_OUT_EXECUTABLES)/strace
RECOVERY_BINARY_SOURCE_FILES += $(TARGET_RECOVERY_ROOT_OUT)/system/bin/hostfs_tool
#TARGET_RECOVERY_DEVICE_MODULES += twrpdec
#RECOVERY_BINARY_SOURCE_FILES += $(TARGET_RECOVERY_ROOT_OUT)/sbin/twrpdec

#
# For local builds only
#
# TWRP zip installer
ifneq ($(wildcard bootable/recovery/installer/.),)
    USE_RECOVERY_INSTALLER := true
    RECOVERY_INSTALLER_PATH := bootable/recovery/installer
endif

# Custom TWRP Versioning
ifneq ($(wildcard device/common/version-info/.),)
    # Uncomment the below line to use custom device version
    include device/common/version-info/custom_twrp_version.mk

    # version prefix is optional - the default value is "LOCAL" if nothing is set in device tree
    #CUSTOM_TWRP_VERSION_PREFIX := CPTB

    ifeq ($(CUSTOM_TWRP_VERSION),)
        CUSTOM_TWRP_VERSION := $(shell date +%Y%m%d)-01
    endif
endif
#
# end local build flags
#

# 设备 vendor 安全补丁级别 (原存在于 vendor.prop, 改为单一来源生成本属性)
VENDOR_SECURITY_PATCH := 2026-02-01

# [真机核查修正] recovery 独立分区 (原厂实测 104857600=100MB), 原厂镜像 kernel_size=0 (ramdisk-only)
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 104857600
BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE := true

# OrangeFox 身份 (编译进 recovery 二进制)
OF_MAINTAINER := serein-213
FOX_DEVICE_MODEL := Xiaomi 17 (pudding)

# 本机 SoC 实际是 sm8850, 但设备树历史上叫 sm8750 ⇒ 让安装包同时接受两个代号
# (OrangeFox 生成器会把它写进 update-binary 的 TARGET_DEVICE_ALT)
FOX_TARGET_DEVICES := sm8750

# [0027b] flashlight: 本机 LED 节点 (white=冷/yellow=暖); orangefox.mk 注入编译宏, 优先级高于主题变量
OF_FL_PATH1 := /sys/class/leds/white:flash-1
OF_FL_PATH2 := /sys/class/leds/yellow:flash-0

# ============================================================
# [0118] 从公开可用参考(YuKongA/twrp_device_xiaomi_sm8750_thales, twrp-16.0)
# 补齐的*关键*开关 —— 此前缺失导致 FBE 解密无法工作:
#   TW_USE_FSCRYPT_POLICY := 2      设备目录策略全是 v2, 缺此则编译出 v1 结构体 ⇒ 策略操作全错
#   TW_INCLUDE_FBE_METADATA_DECRYPT metadata(dm-default-key)解密代码在 partitionmanager.cpp
#                                   里被 #ifdef 包裹, 缺此则整段被编译掉
#   TW_INCLUDE_CRYPTO_FBE           FBE 支持总开关
#   AB_OTA_UPDATER                  本机为 A/B 设备(slot _a)
# ============================================================
TW_INCLUDE_CRYPTO_FBE := true
TW_INCLUDE_FBE_METADATA_DECRYPT := true
TW_USE_FSCRYPT_POLICY := 2
AB_OTA_UPDATER := true
TW_INCLUDE_OMAPI := true
TW_USE_DMCTL := true
RECOVERY_SDCARD_ON_DATA := true
ALLOW_MISSING_DEPENDENCIES := true
BUILD_BROKEN_DUP_RULES := true

# [0127] 编译期默认语言设为中文。默认值是 en 时，首屏(主题启动页/解密页)会在
# 语言包加载之前渲染 —— 实测日志: `I:LANG: en`(第17行) 而 `Loading language 'zh_CN'`
# 在第2718行才出现 ⇒ 解密框用的是英文资源。
TW_DEFAULT_LANGUAGE := zh_CN

# [0132] 设备自有 sepolicy 目录: 只加 dontaudit(免审计), 不放宽 allow.
# 目的: 消除启动阶段 1700+ 条 type=1400 audit 日志(遍历 /data 统计备份大小 +
# 枚举全部属性时被拒的访问)带来的写入开销. 安全语义不变.
BOARD_SEPOLICY_DIRS += device/xiaomi/sm8850_thales/sepolicy

# [0133] 电池改用 sysfs 读取, 不再走 health AIDL binder 轮询
# (TWRP 电池后台线程每秒一次 isDeclared+waitForService, 见 twrp.cpp:555-613)
TW_USE_LEGACY_BATTERY_SERVICES := true

# [0135] 关键: 本机是 **A/B 且带独立 recovery 分区**(实测 by-name/recovery{,_a,_b} 存在).
# 只定义 AB_OTA_UPDATER 会让 twrp-functions.cpp:3203 的预处理器分支误判为
# "无 recovery 分区", 于是解包(用于主题重打包/启动图定制)时去找 /boot 并得到
# 空 block device ⇒ /tmp/orangefox/ramdisk 从不生成 ⇒ 定制被静默丢弃.
# 加上这个开关后走 #else 分支, 正确使用 /recovery.
OF_AB_DEVICE_WITH_RECOVERY_PARTITION := 1

# ============================================================
# [0137] UI 适配 1220x2656 屏幕(圆角 + 居中挖孔)
#   OF_SCREEN_H: 必须与 twres/ui.xml 的 resizing 高度(2351)一致 ——
#     data.cpp:810 会在启动时用它覆盖主题变量 screen_h, 不一致会导致
#     解密界面导航栏按错误高度定位(实测漂移到上方).
#   OF_STATUS_INDENT_*: 默认仅 20 ⇒ 电量/温度被左右 R 角裁切 ⇒ 加大到 64.
#   OF_CLOCK_POS: 0=靠右. 居中会被挖孔摄像头遮挡, 故保持靠右.
#   OF_STATUS_H > 72 才能让 cutout_w(=%status_h%-72) 非零,
#     配合 OF_HIDE_NOTCH=1 使内容整体下移避让挖孔.
# ============================================================
OF_SCREEN_H := 2351
OF_STATUS_H := 120
OF_STATUS_INDENT_LEFT := 64
OF_STATUS_INDENT_RIGHT := 64
OF_CLOCK_POS := 0
OF_HIDE_NOTCH := 1
