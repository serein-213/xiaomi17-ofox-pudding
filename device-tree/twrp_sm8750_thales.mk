#
# Local reconstructed TWRP product definition for Xiaomi sm8750_thales.
#

PRODUCT_PLATFORM := xiaomi_sm8750
DEVICE_PATH := device/xiaomi/sm8750_thales

$(call inherit-product, vendor/twrp/config/common.mk)

PRODUCT_DEVICE := sm8750_thales
PRODUCT_NAME := twrp_sm8750_thales
PRODUCT_BRAND := Xiaomi
PRODUCT_MODEL := 2509FPN0BC
PRODUCT_MANUFACTURER := Xiaomi

$(call inherit-product, $(DEVICE_PATH)/device.mk)
