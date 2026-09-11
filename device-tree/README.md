# TWRP Device Tree for Xiaomi 17 (Pudding)

Device tree for building Team Win Recovery Project (TWRP) for the Xiaomi 17 (Pudding).

**Maintainer:** antocorvo3000

## Device Information

| Property     | Value           |
| ------------ | --------------- |
| Device       | Xiaomi 17       |
| Codename     | Pudding         |
| Manufacturer | Xiaomi          |
| Platform     | Qualcomm Snapdragon (sm8750_thales family) |
| Architecture | arm64           |

## Status

### Working

* Boots successfully
* Touchscreen
* Data decryption — stable
* ADB / Fastbootd

## Notes

The decrypt path in `system/vold/Decrypt.cpp` includes a fix for an AES-256-GCM
authentication-tag handling bug in the synthetic-password unwrap path
(`Decrypt_User_Synth_Pass`): the original code split ciphertext/tag incorrectly,
used an uninitialized tag buffer, and never checked the OpenSSL EVP return
codes. See `patches/0001-vold-fix-synthetic-password-gcm.patch`.

## Credits

* Team Win Recovery Project (TWRP)
* Android Open Source Project (AOSP)
* The Android aftermarket development community
