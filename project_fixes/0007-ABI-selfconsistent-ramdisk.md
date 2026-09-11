# 修复记录 0007: ramdisk ABI 自洽 (源码构建版覆盖 overlay 预编译件)

## 症状 (真机)
- `init.svc.recovery=restarting`; init 每 5s 报 `Service 'recovery' exited with status 1`
- 手动执行: `CANNOT LINK EXECUTABLE "/system/bin/recovery": cannot locate symbol "_Z12gr_draw_rectiiiii"`
- 另缺 `_ZN12KeystoreInfo14backupDatabaseE...`

## 根因
- 设备树 `recovery/root/` 为"自带预编译 blobs"设计 (3652 文件, 含整个 recovery 用户空间)。
- 其 overlay 拷贝 (cp -rf) 覆盖了构建自身的产物: 旧 TWRP 代 `libminuitwrp.so`(350,368, 仅 gr_fill)
  覆盖源码版; 旧 `libkeystoreinfo.so`(35,704, 无 backupDatabase) 同理。
- 新版 OFOX fox_16.0 的 minui 有 `gr_draw_rect` → 动态链接期即死, UI 停在首屏。

## 修复 (两层)
1. **overlay 语义**: overlay 恢复为完整基线 (设备 blobs 必须保留); 由产物树"覆盖回来"。
2. **产物补入** (`build/make/core/Makefile` 0007 patch + 设备树清单):
   - 设备树新增 `recovery_root_from_source.txt` = 215 个"产物树中真实存在"的路径 (由
     overlay∩构建输出/产物树计算; 悬空符号链接 [bionic→/apex] 自动跳过保留 overlay 真文件)。
   - ramdisk 规则在 overlay 之后、安装 recovery 二进制之前, 逐条 `cp` 产物树版本覆盖 ramdisk。
   - 配合 0005 (强制安装自建 recovery 二进制) → 全部关键件均来自同一源码构建。

## 验证 (镜像内)
| 项 | 值 |
|---|---|
| system/bin/recovery | 4,248,272 (含 vold GCM 补丁串) |
| libminuitwrp.so | 333,928, 导出 `gr_draw_rect` ✓ |
| libkeystoreinfo.so | 35,736, 导出 `backupDatabase` ✓ |
| **ABI 闭包** | **UND 826 / 可解析 826 / MISSING=0** ✅ (与设备端同一判定法) |

产物: `BUILDS/OrangeFox-pudding-recovery.img`
SHA256 `016c0e96fe521c265c9d9e6acf50a910bd4ed14bbb4b1048dd8ad4c68aa1f352`
