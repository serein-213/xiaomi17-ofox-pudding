# 修复记录 0011: 品牌/主题层 TWRP -> OrangeFox

## 现象 (用户取证)
二进制含 OrangeFox 特征 (FOX_BUILD_DATE/fox_theme_version/FFiles/foxstart.sh), 但显示层全是 TWRP:
- 设备树 twres/ui.xml = 作者主题 (antocorvo3000 combined_v26, themeversion=6)
- 语言包 23 个为 TWRP 官方包 (fox 键 = 0)
- 图片为 TeamWin 素材; prop.default 无 ro.orangefox.*

## 机制 (取证结论)
- 二进制 `TW_THEME_VERSION = 3` (gui/pages.cpp:61); 版本不匹配 -> "Using stock theme"
- `build/make/core/Makefile` 在 recovery image 阶段调用 `vendor/recovery/OrangeFox_A16.sh`
  (FOX_VENDOR_CMD=Fox_After_Recovery_Image), **仅修补 twres** (pages/resources/themes XML,
  credits/translators/changelog), **不提供主题** -> 主题必须由设备树 recovery/root/twres 提供
- 设备树给了 TWRP 风格主题 => 显示 TWRP

## 修复
1. 归档作者主题 -> project_fixes/twres-author-twrp-theme-20260910.tar.gz (可回退)
2. twres 重建为橙狐主题 (来自 bootable/recovery/gui/theme):
   ui.xml/splash.xml/pages/resources/themes/images 取自 portrait_hdpi (themeversion=3 匹配)
   fonts <- common/fonts; languages <- common/languages + extra-languages (含 zh_CN 74 fox 键)
   体积 21M -> 9.5M
3. 身份注入 (BoardConfig.mk): OF_MAINTAINER := chen / FOX_DEVICE_MODEL := Xiaomi 17 (pudding)
   (orangefox.mk 经 CFLAGS 编入二进制; FOX_BUILD_DATE 运行时取 ro.bootimage.build.date)
4. splash 素材随主题替换 (TeamWin -> OrangeFox)
