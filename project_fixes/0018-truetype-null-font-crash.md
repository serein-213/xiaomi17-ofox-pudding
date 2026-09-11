# 修复记录 0018: GUIInput 字体资源失效 -> twrpTruetype 空指针加锁 (5 秒崩溃循环真因)

## 定位方法 (用户 core dump + 本地符号化)
用户环境无 /system/bin/crash_dump64 (Android 17 移入 runtime APEX) -> tombstone 不可用,
改用 core_pattern 落 core (132MB), 得到寄存器与栈; 我方用二进制内嵌 .gnu_debugdata (迷你调试符号) 符号化:
  PC = libc pthread_mutex_lock, x0 = 0x50   => 对空对象 +0x50 处的 mutex 加锁
  栈: GUIInput::UpdateDisplayText <- GUIInput::NotifyVarChange <- Page::NotifyVarChange
      <- PageSet::NotifyVarChange <- PageManager::SelectPackage <- gui_startPage
      (另有 vsnprintf/__vsprintf_chk 帧)

## 根因 (源码逐字对应)
bootable/recovery/minuitwrp/truetype.cpp:
  int twrpTruetype::gr_ttf_measureEx(const char *s, void *font) {
      TrueTypeFont *f = (TrueTypeFont *)font;
      pthread_mutex_lock(&f->mutex);     // font == NULL -> lock(NULL+0x50) == fault addr 0x50 ✓
调用方 gui/input.cpp:
  GUIInput::UpdateDisplayText(): mFont 非空但 mFont->GetResource() 返回 NULL
  (页面切换 SelectPackage 时字体资源失效/重建, 输入控件持有失效资源)
注: 与主题更换无关(换主题前后同签名); twres/fonts 字体文件齐全(font.xml 引用的 4 个均存在)

## 修复 (四入口判空, 止血且防复发)
truetype.cpp: gr_ttf_measureEx(-1) / gr_ttf_maxExW(0) / gr_ttf_textExWH(-1) / gr_ttf_getMaxFontHeight(0)
均加 `if (f == nullptr) return ...;`

## 同批 (0017)
- bootable/recovery/twrp-functions.cpp: <hal> 无 <name> 时 nameNode->value() 判空
- system/vold/Weaver1.cpp: AIDL/HIDL weaver 均不可用时 mDevice->getConfig() 判空
- 新增 system/bin/twrp-crash-dump.sh (崩溃取证脚本)

## 交付 (build 21)
- 取件码 25094 (img, sha256 3239195e...83fb) / 74012 (zip, sha256 73a21c92...4ccf); 回下载哈希一致
- 验证: truetype.cpp 已重编译; libminuitwrp.so md5 81454d24 -> 7c43d325
- 符号化方法存档: 二进制内嵌 .gnu_debugdata -> objcopy --dump-section + xz -d --format=lzma -> addr2line

## 验收 (用户真机 + 双方复验, build 21)
- 稳定性: 93s 无重启, logcat -b crash 崩溃 0, orbangefox.crash_counter=0,
  实测切页 settings -> ext_general -> settings (原必崩路径) 稳定, 旧 fault addr 0x50 未再出现
- eSE+FBE: isSecureElementPresent:1 / cardPresent:1 -> weaver key size 16 -> User 0 Decrypted Successfully
  -> Data successfully decrypted; /data/media/0 25 项; twrp.user.0.decrypt=1
- NFC 门控: twrp.nfc / odm.nfc_hal_service 均为空也能解密 (QTI SE HAL + se_omapi 足够) => 保持默认关闭
- 镜像侧: sha256 3239195e...83fb 一致; ABI MISSING=0; libminuitwrp 7c43d325; crash-dump 脚本在包内
