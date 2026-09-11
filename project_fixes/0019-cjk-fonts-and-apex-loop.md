# 修复记录 0019: CJK 字体缺失 + APEX loop 挂载 EOVERFLOW

## 1) 中文不显示 (主题缺 CJK 字体)
- 机制: 语言文件 (extra-languages/languages/zh_CN.xml) 用
  `<resource name="body1" type="fontoverride" filename="DroidSansFallback.ttf" scale="100"/>`
  即按语言覆盖字体 -> 要求 /twres/fonts/DroidSansFallback.ttf 存在
- 我们的主题替换只拷了 extra-languages 的 **languages**, 漏了 **fonts** => 中文缺字
- 修复: 把 bootable/recovery/gui/theme/extra-languages/fonts/*
  (DroidSansFallback.ttf 3.9MB, NotoSansCJKjp-Regular.ttf 709KB, Roboto-Spanish.ttf, ae_Cortoba.ttf)
  拷入 twres/fonts/ (双树)

## 2) recovery 中 APEX 挂载失败 (EOVERFLOW)
- 真机: `E:failed to mount loop: /tmp/com.android.apex.cts.shim.apex: Value too large for defined data type`
- 根因 (bootable/recovery/twrpApex.cpp loadApexImage):
    close(fd);                              // 先关闭后端文件
    off_t apex_size = lseek(fd, 0, SEEK_END);  // 已关闭 -> -1
    info.lo_sizelimit = apex_size;             // 0xFFFFFFFFFFFFFFFF
    ioctl(loop_fd, LOOP_SET_STATUS64, &info)   // 内核 EOVERFLOW(75) ✓与真机报错逐字对应
- 修复: 先取 size 再 close; size<=0 时明确报错返回

## 3) DrmLibFs 重试噪音 (未改, 说明)
- 写者: vendor/bin/qseecomd (TEE 守护进程, 不可停) dlopen vendor/lib64/libdrmfs.so
- 原因: recovery 未挂载 /persist (fstab 有该条目, 分区 persist -> /dev/block/sdf7)
- 处理: 保持原样(纯日志噪音, 151 行/会话); 需要静音时可手动在 recovery UI 挂载 /persist

## 交付 (build 22)
- 取件码 37466 (img, sha256 9c6c04d9…de54) / 23302 (zip, sha256 372d1160…45a1); 回下载哈希一致
- 落包验证: twres/fonts 含 DroidSansFallback.ttf 3939852 / NotoSansCJKjp-Regular.ttf 709712 /
  Roboto-Spanish.ttf 170984 / ae_Cortoba.ttf 109928; 主题结构 pages/resources/themes ✓; 语言 17 ✓;
  keymint=2 ✓; recovery 4248392 (twrpApex.cpp 已重编译)
