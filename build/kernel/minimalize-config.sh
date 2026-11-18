#!/bin/bash
# Transform Fedora's x86_64 kernel config into a minimal Xen guest kernel config.
# Strategy: Only disable major subsystems with no dependencies in what we keep.
# Keep everything else at Fedora defaults — the kernel config system handles
# dependency resolution, and the spec requires source config to match generated.
#
# Usage: minimalize-config.sh <input-config> [output-config]

set -euo pipefail

INPUT="${1:?Usage: $0 <input-config> [output-config]}"
OUTPUT="${2:-/dev/stdout}"

# Return 0 to disable, 1 to keep
should_disable() {
    local opt="$1"

    # ===== SOUND — nothing we keep depends on this =====
    if [[ "$opt" == SND* ]] || [[ "$opt" == SOUND ]] || [[ "$opt" == AC97* ]] || \
       [[ "$opt" == ALSA* ]] || [[ "$opt" == SOUNDWIRE* ]] || [[ "$opt" == HDA* ]]; then
        return 0
    fi

    # ===== GPU/Display — Xen provides virtual framebuffer =====
    # Keep FB_EFI — needed for proper x86_64 boot flags
    [[ "$opt" == FB_EFI ]] && return 1
    if [[ "$opt" == DRM* ]] || [[ "$opt" == FB_* ]] || [[ "$opt" == VGA_CONSOLE ]] || \
       [[ "$opt" == VIDEO* ]] || [[ "$opt" == GSPMI* ]] || [[ "$opt" == MIPI* ]] || \
       [[ "$opt" == MEDIA* ]] || [[ "$opt" == DVB_* ]] || [[ "$opt" == V4L* ]] || \
       [[ "$opt" == ANALOGTV ]] || [[ "$opt" == DAC1010 ]] || [[ "$opt" == DAC7010A ]] || \
       [[ "$opt" == DAC7512 ]] || [[ "$opt" == DAC7561 ]] || [[ "$opt" == DAC756 ]] || \
       [[ "$opt" == ADC* ]] && [[ "$opt" != ADC_EXYNOS ]] || \
       [[ "$opt" == GPU_VID_MEM ]] || [[ "$opt" == DRM_KMS_HELPER ]] || \
       [[ "$opt" == DRM_KMS_FB_HELPER ]] || [[ "$opt" == DRM_KMS_CMA_HELPER ]] || \
       [[ "$opt" == DRM_TTM ]] || [[ "$opt" == DRM_GEM ]] || \
       [[ "$opt" == DRM_DP_AUX_BUS ]] || [[ "$opt" == DRM_DP_CEC ]] || \
       [[ "$opt" == DRM_DP_HELPER ]] || [[ "$opt" == DRM_DP_AUX_NATIVE ]] || \
       [[ "$opt" == DRM_I2C_* ]] || [[ "$opt" == DRM_KMS_HELPER ]] || \
       [[ "$opt" == DRM_LOAD_EDID_FIRMWARE ]] || [[ "$opt" == DRM_MIPI_DSI ]] || \
       [[ "$opt" == DRM_PANEL ]] || [[ "$opt" == DRM_TINYDRM ]] || \
       [[ "$opt" == DRM_VGEM ]] || [[ "$opt" == DRM_VKMS ]] || \
       [[ "$opt" == DRM_XGBe ]] || [[ "$opt" == DRM_XEN ]] || \
       [[ "$opt" == FRAMEBUFFER ]] || [[ "$opt" == FB ]] || \
       [[ "$opt" == BACKLIGHT ]] || [[ "$opt" == BACKLIGHT_* ]] || \
       [[ "$opt" == LEDS ]] || [[ "$opt" == LEDS_* ]] || \
       [[ "$opt" == VIDEO_OUTPUT ]] || [[ "$opt" == VIDEO_SELECT ]]; then
        return 0
    fi

    # ===== USB HOST — guests don't need USB controllers =====
    # Keep USB core and gadget (might be needed for virtio)
    if [[ "$opt" == USB_HCD ]] || [[ "$opt" == USB_XHCI_HCD ]] || \
       [[ "$opt" == USB_EHCI_HCD ]] || [[ "$opt" == USB_OHCI_HCD ]] || \
       [[ "$opt" == USB_UHCI_HCD ]] || [[ "$opt" == USB_R8A66597_HCD ]] || \
       [[ "$opt" == USB_RCAR_HCD ]] || [[ "$opt" == USB_MUSB_HDRC ]] || \
       [[ "$opt" == USB_MUSB_* ]] || [[ "$opt" == USB_DWC3 ]] || \
       [[ "$opt" == USB_DWC2 ]] || [[ "$opt" == USB_CHIPIDEA ]] || \
       [[ "$opt" == USB_ISP116X_HCD ]] || [[ "$opt" == USB_ISP1362_HCD ]] || \
       [[ "$opt" == USB_SL811_HCD ]] || [[ "$opt" == USB_PXA27X ]] || \
       [[ "$opt" == USB_MV ]] || [[ "$opt" == USB_OXU210HP_HCD ]] || \
       [[ "$opt" == USB_PESC ]] || [[ "$opt" == USB_RCAR_GEN2 ]] || \
       [[ "$opt" == USB_SISUSBHCD ]] || [[ "$opt" == USB_USBNET ]] || \
       [[ "$opt" == USB_NET_DRIVERS ]] || [[ "$opt" == USB_MON ]] || \
       [[ "$opt" == USB_STORAGE ]] || [[ "$opt" == USB_LIBUSUAL ]] || \
       [[ "$opt" == USB_MICROFILE ]] || [[ "$opt" == USB_IMAGE ]] || \
       [[ "$opt" == USB_PRINTER ]] || [[ "$opt" == USB_ACM ]] || \
       [[ "$opt" == USB_SERIAL ]] || [[ "$opt" == USB_SERIAL_* ]] || \
       [[ "$opt" == USB_HID ]] || [[ "$opt" == USB/input ]] || \
       [[ "$opt" == USB_USS720 ]] || [[ "$opt" == USB_EMI62 ]] || \
       [[ "$opt" == USB_ADUTUX ]] || [[ "$opt" == USB_SEVSEG ]] || \
       [[ "$opt" == USB_RIO500 ]] || [[ "$opt" == USB_LEGOTOWER ]] || \
       [[ "$opt" == USB_APPLEDISPLAY ]] || [[ "$opt" == USB_IDMOUSE ]] || \
       [[ "$opt" == USB_MOS7720 ]] || [[ "$opt" == USB_MOS7840 ]] || \
       [[ "$opt" == USB_CYTHERM ]] || [[ "$opt" == USB_EZUSB_FX2 ]] || \
       [[ "$opt" == USB_BUDGET_KEYPAD ]] || [[ "$opt" == USB_ATM ]] || \
       [[ "$opt" == USB_SPEEDTOUCH ]] || [[ "$opt" == USB_CXACRU ]] || \
       [[ "$opt" == USB_UEAGLEATM ]] || [[ "$opt" == USB_XUSBATM ]] || \
       [[ "$opt" == USB_PHIDGETSERVO ]] || [[ "$opt" == USB_IDE ]] || \
       [[ "$opt" == USB_IPACK ]] || [[ "$opt" == USB_MIDI ]] || \
       [[ "$opt" == USB_MIDI_* ]] || [[ "$opt" == USB_RAWGADIO ]] || \
       [[ "$opt" == USB_MIDI_GADGET ]] || [[ "$opt" == USB_GADGET ]] || \
       [[ "$opt" == USB_F_* ]] || [[ "$opt" == USB_CONFIGFS ]] || \
       [[ "$opt" == USB_DWC3_GADGET ]] || [[ "$opt" == USB_DWC3_DUAL_ROLE ]] || \
       [[ "$opt" == USB_DWC2_DUAL_ROLE ]] || [[ "$opt" == USB_MUSB_DUAL_ROLE ]] || \
       [[ "$opt" == USB_RCAR_DMAC ]] || [[ "$opt" == USB_BDC ]] || \
       [[ "$opt" == USB_HCD_* ]] || [[ "$opt" == USB_OTG ]] || \
       [[ "$opt" == USB_OTG_FSM ]] || [[ "$opt" == USB_LED_TRIG ]] || \
       [[ "$opt" == USB_U1 ]] || [[ "$opt" == USB_U2 ]] || \
       [[ "$opt" == USB_SUSPEND ]] || [[ "$opt" == USB_PCI ]] || \
       [[ "$opt" == USB_PLATFORM ]] || [[ "$opt" == USB_OF ]] || \
       [[ "$opt" == USB_XHCI_PCI ]] || [[ "$opt" == USB_XHCI_PCI_RENESAS ]] || \
       [[ "$opt" == USB_XHCI_PLATFORM ]] || [[ "$opt" == USB_XHCI_HCD_PCI ]] || \
       [[ "$opt" == USB_XHCI_HCD_PLATFORM ]] || [[ "$opt" == USB_XHCI_MTK ]] || \
       [[ "$opt" == USB_XHCI_INTEL ]] || [[ "$opt" == USB_XHCI_DBGCAP ]] || \
       [[ "$opt" == USB_XHCI_TRACE ]] || [[ "$opt" == USB_XHCI_TUSB ]] || \
       [[ "$opt" == USB_EHCI_PCI ]] || [[ "$opt" == USB_EHCI_HCD_PCI ]] || \
       [[ "$opt" == USB_EHCI_HCD_PLATFORM ]] || [[ "$opt" == USB_EHCI_FSL ]] || \
       [[ "$opt" == USB_EHCI_TEGRA ]] || [[ "$opt" == USB_EHCI_HCD_OMAP ]] || \
       [[ "$opt" == USB_EHCI_MV ]] || [[ "$opt" == USB_OHCI_PCI ]] || \
       [[ "$opt" == USB_OHCI_HCD_PCI ]] || [[ "$opt" == USB_OHCI_HCD_PLATFORM ]] || \
       [[ "$opt" == USB_UHCI_HCD ]] || [[ "$opt" == USB_U132_HCD ]] || \
       [[ "$opt" == USB_SL811_HCD ]] || [[ "$opt" == USB_RCAR_HCD ]] || \
       [[ "$opt" == USB_ISP116X_HCD ]] || [[ "$opt" == USB_ISP1362_HCD ]] || \
       [[ "$opt" == USB_MUSB_TUSB6010 ]] || [[ "$opt" == USB_MUSB_DA8XX ]] || \
       [[ "$opt" == USB_MUSB_AM35X ]] || [[ "$opt" == USB_MUSB_UX500 ]] || \
       [[ "$opt" == USB_MUSB_DSPS ]] || [[ "$opt" == USB_MUSB_HOST ]] || \
       [[ "$opt" == USB_MUSB_GADGET ]] || [[ "$opt" == USB_MUSB_UX500 ]] || \
       [[ "$opt" == USB_DWC3 ]] || [[ "$opt" == USB_DWC3_DUAL_ROLE ]] || \
       [[ "$opt" == USB_DWC3_HOST ]] || [[ "$opt" == USB_DWC3_GADGET ]] || \
       [[ "$opt" == USB_DWC3_OF_SIMPLE ]] || [[ "$opt" == USB_DWC3_QCOM ]] || \
       [[ "$opt" == USB_DWC3_MTK ]] || [[ "$opt" == USB_DWC3_EXYNOS ]] || \
       [[ "$opt" == USB_DWC3_HAPS ]] || [[ "$opt" == USB_DWC3_K3 ]] || \
       [[ "$opt" == USB_DWC3_ST ]] || [[ "$opt" == USB_DWC3_SPEAR ]] || \
       [[ "$opt" == USB_DWC3_IMX ]] || [[ "$opt" == USB_DWC3_INTEL ]] || \
       [[ "$opt" == USB_DWC3_LGM ]] || [[ "$opt" == USB_DWC3_MESON ]] || \
       [[ "$opt" == USB_DWC3_OMAP ]] || [[ "$opt" == USB_DWC3_PCI ]] || \
       [[ "$opt" == USB_DWC3_RCAR ]] || [[ "$opt" == USB_DWC3_BERR ]] || \
       [[ "$opt" == USB_DWC3_TRBE ]] || [[ "$opt" == USB_DWC2 ]] || \
       [[ "$opt" == USB_DWC2_DUAL_ROLE ]] || [[ "$opt" == USB_DWC2_HOST ]] || \
       [[ "$opt" == USB_DWC2_GADGET ]] || [[ "$opt" == USB_DWC2_OMAP ]] || \
       [[ "$opt" == USB_DWC2_BERLIN ]] || [[ "$opt" == USB_DWC2_MESON_G12A ]] || \
       [[ "$opt" == USB_DWC2_IMX ]] || [[ "$opt" == USB_CHIPIDEA_UDC ]] || \
       [[ "$opt" == USB_CHIPIDEA_HOST ]] || [[ "$opt" == USB_CHIPIDEA_PCI ]] || \
       [[ "$opt" == USB_CHIPIDEA_MTK ]] || [[ "$opt" == USB_CHIPIDEA_XILINX ]] || \
       [[ "$opt" == USB_HSIC_HOST ]] || [[ "$opt" == USB_HSIC ]] || \
       [[ "$opt" == USB_RCAR_GEN2 ]] || [[ "$opt" == USB_RCAR_USB2 ]] || \
       [[ "$opt" == USB_RCAR_USB3 ]] || [[ "$opt" == USB_PXA27X ]] || \
       [[ "$opt" == USB_MV ]] || [[ "$opt" == USB_OXU210HP_HCD ]] || \
       [[ "$opt" == USB_PESC ]] || [[ "$opt" == USB_SISUSBVGD_HCD ]] || \
       [[ "$opt" == USB_SISUSBHCD ]] || [[ "$opt" == USB_USBNET ]] || \
       [[ "$opt" == USB_NET_DRIVERS ]] || [[ "$opt" == USB_CDC_* ]] || \
       [[ "$opt" == USB_HSO ]] || [[ "$opt" == USB_IPHETH ]] || \
       [[ "$opt" == USB_KAWETH ]] || [[ "$opt" == USB_PEGASUS ]] || \
       [[ "$opt" == USB_RTL8150 ]] || [[ "$opt" == USB_RTL8152 ]] || \
       [[ "$opt" == USB_LAN78XX ]] || [[ "$opt" == USB_USBNET ]] || \
       [[ "$opt" == USB_NET_AX8817X ]] || [[ "$opt" == USB_NET_AX88179_178A ]] || \
       [[ "$opt" == USB_NET_CDCETHER ]] || [[ "$opt" == USB_NET_CDC_EEM ]] || \
       [[ "$opt" == USB_NET_CDC_NCM ]] || [[ "$opt" == USB_NET_HUAWEI_CDC_NCM ]] || \
       [[ "$opt" == USB_NET_ZAURUS ]] || [[ "$opt" == USB_NET_NET1080 ]] || \
       [[ "$opt" == USB_NET_PLUSB ]] || [[ "$opt" == USB_NET_CDC_SUBSET ]] || \
       [[ "$opt" == USB_NET_MCS7830 ]] || [[ "$opt" == USB_NET_RNDIS_HOST ]] || \
       [[ "$opt" == USB_NET_CDC_MBIM ]] || [[ "$opt" == USB_NET_INT51X1 ]] || \
       [[ "$opt" == USB_MON ]] || [[ "$opt" == USB_STORAGE ]] || \
       [[ "$opt" == USB_LIBUSUAL ]] || [[ "$opt" == USB_STORAGE_DATAFAB ]] || \
       [[ "$opt" == USB_STORAGE_FREECOM ]] || [[ "$opt" == USB_STORAGE_ISD200 ]] || \
       [[ "$opt" == USB_STORAGE_USBAT ]] || [[ "$opt" == USB_STORAGE_UAS ]] || \
       [[ "$opt" == USB_STORAGE_UAS ]] || [[ "$opt" == USB_MICROFILE ]] || \
       [[ "$opt" == USB_IMAGE ]] || [[ "$opt" == USB_PRINTER ]] || \
       [[ "$opt" == USB_ACM ]] || [[ "$opt" == USB_ACM_WMT ]] || \
       [[ "$opt" == USB_SERIAL ]] || [[ "$opt" == USB_SERIAL_SIMPLE ]] || \
       [[ "$opt" == USB_SERIAL_AIRCABLE ]] || [[ "$opt" == USB_SERIAL_ARK3116 ]] || \
       [[ "$opt" == USB_SERIAL_BELKIN ]] || [[ "$opt" == USB_SERIAL_CH341 ]] || \
       [[ "$opt" == USB_SERIAL_WHITEHEAT ]] || [[ "$opt" == USB_SERIAL_CP210X ]] || \
       [[ "$opt" == USB_SERIAL_CYPRESS_M8 ]] || [[ "$opt" == USB_SERIAL_FTDI_SIO ]] || \
       [[ "$opt" == USB_SERIAL_VISOR ]] || [[ "$opt" == USB_SERIAL_IPAQ ]] || \
       [[ "$opt" == USB_SERIAL_KEYSPAN ]] || [[ "$opt" == USB_SERIAL_KEYSPAN_PDA ]] || \
       [[ "$opt" == USB_SERIAL_KEYSPAN_MPR ]] || [[ "$opt" == USB_SERIAL_IOEDGE ]] || \
       [[ "$opt" == USB_SERIAL_OTI6858 ]] || [[ "$opt" == USB_SERIAL_PL2303 ]] || \
       [[ "$opt" == USB_SERIAL_QCAUX ]] || [[ "$opt" == USB_SERIAL_QUALCOMM ]] || \
       [[ "$opt" == USB_SERIAL_SIERRAWIRELESS ]] || [[ "$opt" == USB_SERIAL_SYMBOL ]] || \
       [[ "$opt" == USB_SERIAL_TI ]] || [[ "$opt" == USB_SERIAL_USBTVT ]] || \
       [[ "$opt" == USB_SERIAL_WISHBONE ]] || [[ "$opt" == USB_HID ]] || \
       [[ "$opt" == USB_HID_PID ]] || [[ "$opt" == USB_HID_A4TECH ]] || \
       [[ "$opt" == USB_HID_ACCUTOUCH ]] || [[ "$opt" == USB_HID_ACRUX ]] || \
       [[ "$opt" == USB_HID_APPLE ]] || [[ "$opt" == USB_HID_APPLETOUCH ]] || \
       [[ "$opt" == USB_HID_ASUS ]] || [[ "$opt" == USB_HID_BELKIN ]] || \
       [[ "$opt" == USB_HID_CHERRY ]] || [[ "$opt" == USB_HID_CHICONY ]] || \
       [[ "$opt" == USB_HID_CYPRESS ]] || [[ "$opt" == USB_HID_DRAGONRISE ]] || \
       [[ "$opt" == USB_HID_EMS_FF ]] || [[ "$opt" == USB_HID_ELAN ]] || \
       [[ "$opt" == USB_HID_ELECOM ]] || [[ "$opt" == USB_HID_EZKEY ]] || \
       [[ "$opt" == USB_HID_GEMBIRD ]] || [[ "$opt" == USB_HID_GENIUS ]] || \
       [[ "$opt" == USB_HID_GTCO ]] || [[ "$opt" == USB_HID_KENSINGTON ]] || \
       [[ "$opt" == USB_HID_KEYTOUCH ]] || [[ "$opt" == USB_HID_KYE ]] || \
       [[ "$opt" == USB_HID_LOGITECH ]] || [[ "$opt" == USB_HID_LOGITECH_DJ ]] || \
       [[ "$opt" == USB_HID_LOGITECH_HIDPP ]] || [[ "$opt" == USB_HID_MAGICMOUSE ]] || \
       [[ "$opt" == USB_HID_MICROSOFT ]] || [[ "$opt" == USB_HID_MONTEREY ]] || \
       [[ "$opt" == USB_HID_MULTITOUCH ]] || [[ "$opt" == USB_HID_NTRIG ]] || \
       [[ "$opt" == USB_HID_ORTEK ]] || [[ "$opt" == USB_HID_PANTHERLORD ]] || \
       [[ "$opt" == USB_HID_PENMOUNT ]] || [[ "$opt" == USB_HID_PETALYNX ]] || \
       [[ "$opt" == USB_HID_PICOTECH ]] || [[ "$opt" == USB_HID_PRIMAX ]] || \
       [[ "$opt" == USB_HID_ROCCAT ]] || [[ "$opt" == USB_HID_SAITEK ]] || \
       [[ "$opt" == USB_HID_SONY ]] || [[ "$opt" == USB_HID_SPEEDLINK ]] || \
       [[ "$opt" == USB_HID_STEELSERIES ]] || [[ "$opt" == USB_HID_SUNPLUS ]] || \
       [[ "$opt" == USB_HID_RMI ]] || [[ "$opt" == USB_HID_GREENASIA ]] || \
       [[ "$opt" == USB_HID_SMARTJOYPLUS ]] || [[ "$opt" == USB_HID_TIVO ]] || \
       [[ "$opt" == USB_HID_TOPSEED ]] || [[ "$opt" == USB_HID_THRUSTMASTER ]] || \
       [[ "$opt" == USB_HID_UCLOGIC ]] || [[ "$opt" == USB_HID_WALTOP ]] || \
       [[ "$opt" == USB_HID_XINMOONS ]] || [[ "$opt" == USB_HID_XIAOMI ]] || \
       [[ "$opt" == USB_OINK ]] || [[ "$opt" == USB_USS720 ]] || \
       [[ "$opt" == USB_EMI62 ]] || [[ "$opt" == USB_ADUTUX ]] || \
       [[ "$opt" == USB_SEVSEG ]] || [[ "$opt" == USB_RIO500 ]] || \
       [[ "$opt" == USB_LEGOTOWER ]] || [[ "$opt" == USB_APPLEDISPLAY ]] || \
       [[ "$opt" == USB_IDMOUSE ]] || [[ "$opt" == USB_MOS7720 ]] || \
       [[ "$opt" == USB_MOS7840 ]] || [[ "$opt" == USB_CYTHERM ]] || \
       [[ "$opt" == USB_EZUSB_FX2 ]] || [[ "$opt" == USB_BUDGET_KEYPAD ]] || \
       [[ "$opt" == USB_ATM ]] || [[ "$opt" == USB_SPEEDTOUCH ]] || \
       [[ "$opt" == USB_CXACRU ]] || [[ "$opt" == USB_UEAGLEATM ]] || \
       [[ "$opt" == USB_XUSBATM ]] || [[ "$opt" == USB_PHIDGETSERVO ]] || \
       [[ "$opt" == USB_IDE ]] || [[ "$opt" == USB_IPACK ]] || \
       [[ "$opt" == USB_IPACK_DATACABLE ]] || [[ "$opt" == USB_IPACK_IDE ]] || \
       [[ "$opt" == USB_MIDI ]] || [[ "$opt" == USB_MIDI_GADGET ]] || \
       [[ "$opt" == USB_RAWGADIO ]] || [[ "$opt" == USB_GADGET ]] || \
       [[ "$opt" == USB_GADGET_DEBUG ]] || [[ "$opt" == USB_GADGETFS ]] || \
       [[ "$opt" == USB_CONFIGFS ]] || [[ "$opt" == USB_F_* ]] || \
       [[ "$opt" == USB_MASS_STORAGE ]] || [[ "$opt" == USB_MASS_STORAGE_* ]] || \
       [[ "$opt" == USB_FUNCTIONFS ]] || [[ "$opt" == USB_LIBCOMPOSITE ]] || \
       [[ "$opt" == USB_U_SERIAL ]] || [[ "$opt" == USB_U_AUDIO ]] || \
       [[ "$opt" == USB_U_MIDI ]] || [[ "$opt" == USB_U_MIDI_GADGET ]] || \
       [[ "$opt" == USB_U_PRINTER ]] || [[ "$opt" == USB_U_ACM ]] || \
       [[ "$opt" == USB_U_SERIAL ]] || [[ "$opt" == USB_U_ETHER ]] || \
       [[ "$opt" == USB_U_HID ]] || [[ "$opt" == USB_U_MASS_STORAGE ]] || \
       [[ "$opt" == USB_U_FUNCTION ]] || [[ "$opt" == USB_U_ZERO ]] || \
       [[ "$opt" == USB_U_GADGET ]] || [[ "$opt" == USB_U_GADGETS ]] || \
       [[ "$opt" == USB_DWC3_GADGET ]] || [[ "$opt" == USB_DWC3_DUAL_ROLE ]] || \
       [[ "$opt" == USB_DWC2_DUAL_ROLE ]] || [[ "$opt" == USB_MUSB_DUAL_ROLE ]] || \
       [[ "$opt" == USB_RCAR_DMAC ]] || [[ "$opt" == USB_BDC ]] || \
       [[ "$opt" == USB_LED_TRIG ]] || [[ "$opt" == USB_U1 ]] || \
       [[ "$opt" == USB_U2 ]] || [[ "$opt" == USB_SUSPEND ]] || \
       [[ "$opt" == USB_PCI ]] || [[ "$opt" == USB_PLATFORM ]] || \
       [[ "$opt" == USB_OF ]] || [[ "$opt" == USB_XHCI_PCI ]] || \
       [[ "$opt" == USB_XHCI_PCI_RENESAS ]] || [[ "$opt" == USB_XHCI_PLATFORM ]] || \
       [[ "$opt" == USB_XHCI_HCD_PCI ]] || [[ "$opt" == USB_XHCI_HCD_PLATFORM ]] || \
       [[ "$opt" == USB_XHCI_MTK ]] || [[ "$opt" == USB_XHCI_INTEL ]] || \
       [[ "$opt" == USB_XHCI_DBGCAP ]] || [[ "$opt" == USB_XHCI_TRACE ]] || \
       [[ "$opt" == USB_XHCI_TUSB ]] || [[ "$opt" == USB_EHCI_PCI ]] || \
       [[ "$opt" == USB_EHCI_HCD_PCI ]] || [[ "$opt" == USB_EHCI_HCD_PLATFORM ]] || \
       [[ "$opt" == USB_EHCI_FSL ]] || [[ "$opt" == USB_EHCI_TEGRA ]] || \
       [[ "$opt" == USB_EHCI_HCD_OMAP ]] || [[ "$opt" == USB_EHCI_MV ]] || \
       [[ "$opt" == USB_OHCI_PCI ]] || [[ "$opt" == USB_OHCI_HCD_PCI ]] || \
       [[ "$opt" == USB_OHCI_HCD_PLATFORM ]] || [[ "$opt" == USB_UHCI_HCD ]] || \
       [[ "$opt" == USB_U132_HCD ]] || [[ "$opt" == USB_SL811_HCD ]] || \
       [[ "$opt" == USB_RCAR_HCD ]] || [[ "$opt" == USB_ISP116X_HCD ]] || \
       [[ "$opt" == USB_ISP1362_HCD ]] || [[ "$opt" == USB_MUSB_TUSB6010 ]] || \
       [[ "$opt" == USB_MUSB_DA8XX ]] || [[ "$opt" == USB_MUSB_AM35X ]] || \
       [[ "$opt" == USB_MUSB_UX500 ]] || [[ "$opt" == USB_MUSB_DSPS ]] || \
       [[ "$opt" == USB_MUSB_HOST ]] || [[ "$opt" == USB_MUSB_GADGET ]] || \
       [[ "$opt" == USB_MUSB_UX500 ]] || [[ "$opt" == USB_DWC3 ]] || \
       [[ "$opt" == USB_DWC3_DUAL_ROLE ]] || [[ "$opt" == USB_DWC3_HOST ]] || \
       [[ "$opt" == USB_DWC3_GADGET ]] || [[ "$opt" == USB_DWC3_OF_SIMPLE ]] || \
       [[ "$opt" == USB_DWC3_QCOM ]] || [[ "$opt" == USB_DWC3_MTK ]] || \
       [[ "$opt" == USB_DWC3_EXYNOS ]] || [[ "$opt" == USB_DWC3_HAPS ]] || \
       [[ "$opt" == USB_DWC3_K3 ]] || [[ "$opt" == USB_DWC3_ST ]] || \
       [[ "$opt" == USB_DWC3_SPEAR ]] || [[ "$opt" == USB_DWC3_IMX ]] || \
       [[ "$opt" == USB_DWC3_INTEL ]] || [[ "$opt" == USB_DWC3_LGM ]] || \
       [[ "$opt" == USB_DWC3_MESON ]] || [[ "$opt" == USB_DWC3_OMAP ]] || \
       [[ "$opt" == USB_DWC3_PCI ]] || [[ "$opt" == USB_DWC3_RCAR ]] || \
       [[ "$opt" == USB_DWC3_BERR ]] || [[ "$opt" == USB_DWC3_TRBE ]] || \
       [[ "$opt" == USB_DWC2 ]] || [[ "$opt" == USB_DWC2_DUAL_ROLE ]] || \
       [[ "$opt" == USB_DWC2_HOST ]] || [[ "$opt" == USB_DWC2_GADGET ]] || \
       [[ "$opt" == USB_DWC2_OMAP ]] || [[ "$opt" == USB_DWC2_BERLIN ]] || \
       [[ "$opt" == USB_DWC2_MESON_G12A ]] || [[ "$opt" == USB_DWC2_IMX ]] || \
       [[ "$opt" == USB_CHIPIDEA_UDC ]] || [[ "$opt" == USB_CHIPIDEA_HOST ]] || \
       [[ "$opt" == USB_CHIPIDEA_PCI ]] || [[ "$opt" == USB_CHIPIDEA_MTK ]] || \
       [[ "$opt" == USB_CHIPIDEA_XILINX ]] || [[ "$opt" == USB_HSIC_HOST ]] || \
       [[ "$opt" == USB_HSIC ]] || [[ "$opt" == USB_RCAR_GEN2 ]] || \
       [[ "$opt" == USB_RCAR_USB2 ]] || [[ "$opt" == USB_RCAR_USB3 ]] || \
       [[ "$opt" == USB_PXA27X ]] || [[ "$opt" == USB_MV ]] || \
       [[ "$opt" == USB_OXU210HP_HCD ]] || [[ "$opt" == USB_PESC ]] || \
       [[ "$opt" == USB_SISUSBVGD_HCD ]] || [[ "$opt" == USB_SISUSBHCD ]] || \
       [[ "$opt" == USB_TYPEC ]] || [[ "$opt" == USB4 ]]; then
        return 0
    fi

    # ===== STORAGE CONTROLLERS — use xen-blkfront/virtio-blk =====
    if [[ "$opt" == SCSI_* ]] && [[ "$opt" != SCSI ]] && \
       [[ "$opt" != SCSI_CONSTANTS ]] && [[ "$opt" != SCSI_LOWLEVEL ]] && \
       [[ "$opt" != SCSI_PROC_FS ]] && [[ "$opt" != SCSI_LOGGING ]] && \
       [[ "$opt" != SCSI_SCAN_ASYNC ]] && [[ "$opt" != SCSI_SAS_ATA ]] && \
       [[ "$opt" != SCSI_VIRTIO ]] && [[ "$opt" != SCSI_SPI_ATTRS ]] && \
       [[ "$opt" != SCSI_SAS_ATTRS ]] && [[ "$opt" != SCSI_SRP_ATTRS ]] && \
       [[ "$opt" != SCSI_FC_ATTRS ]] && [[ "$opt" != SCSI_DH ]] && \
       [[ "$opt" != SCSI_DH_* ]] && [[ "$opt" != SCSI_UFSHCD ]] && \
       [[ "$opt" != SCSI_UFS* ]] && [[ "$opt" != SCSI_ENCLOSURE ]] && \
       [[ "$opt" != SCSI_LIBFC ]] && [[ "$opt" != SCSI_ISCSI_ATTRS ]] && \
       [[ "$opt" != SCSI_ISCSI ]] && [[ "$opt" != SCSI_ISCSI_TCP ]] && \
       [[ "$opt" != SCSI_ISCSI_BOOT_SYSFS ]] && [[ "$opt" != SCSI_ISCSI_ERR ]] && \
       [[ "$opt" != SCSI_ISCSI_ERR_REC ]] && [[ "$opt" != SCSI_ISCSI_BOOT ]] && \
       [[ "$opt" != SCSI_ISCSI_ATTRS ]] && [[ "$opt" != SCSI_ISCSI ]] && \
       [[ "$opt" != SCSI_ISCSI_TCP ]] && [[ "$opt" != SCSI_ISCSI_BOOT ]] && \
       [[ "$opt" != SCSI_ISCSI_ERR ]] && [[ "$opt" != SCSI_ISCSI_ERR_REC ]] && \
       [[ "$opt" != SCSI_ISCSI_BOOT_SYSFS ]]; then
        return 0
    fi
    if [[ "$opt" == IDE* ]] || [[ "$opt" == SATA* ]] || [[ "$opt" == AHCI* ]] || \
       [[ "$opt" == MEGAR* ]] || [[ "$opt" == MPT* ]] || [[ "$opt" == MVSAS* ]] || \
       [[ "$opt" == MVUMI* ]] || [[ "$opt" == MYRB* ]] || [[ "$opt" == MYRS* ]] || \
       [[ "$opt" == HPSA* ]] || [[ "$opt" == IPS* ]] || [[ "$opt" == IPR* ]] || \
       [[ "$opt" == IPRA* ]] || [[ "$opt" == ISP* ]] || [[ "$opt" == INIA100* ]] || \
       [[ "$opt" == INITIO* ]] || [[ "$opt" == IMATEL* ]] || [[ "$opt" == IMM* ]] || \
       [[ "$opt" == ISCI* ]] || [[ "$opt" == ISCSI_* ]] || [[ "$opt" == HPT* ]] || \
       [[ "$opt" == HISI_SAS* ]] || [[ "$opt" == FDOMAIN* ]] || [[ "$opt" == EFCT* ]] || \
       [[ "$opt" == ESAS* ]] || [[ "$opt" == DMX* ]] || [[ "$opt" == DC395* ]] || \
       [[ "$opt" == CHELSIO* ]] || [[ "$opt" == CXGB* ]] || [[ "$opt" == CXL* ]] || \
       [[ "$opt" == BNX2* ]] || [[ "$opt" == BNX2X* ]] || [[ "$opt" == BFA* ]] || \
       [[ "$opt" == ARCMSR* ]] || [[ "$opt" == AACRAID* ]] || [[ "$opt" == ADP* ]] || \
       [[ "$opt" == AIC7* ]] || [[ "$opt" == AIC9* ]] || [[ "$opt" == AM53C* ]] || \
       [[ "$opt" == 3W_* ]] || [[ "$opt" == BUSLOGIC* ]] || [[ "$opt" == WD719* ]] || \
       [[ "$opt" == QLOGIC* ]] || [[ "$opt" == QLA* ]] || [[ "$opt" == STEX* ]] || \
       [[ "$opt" == SYM53C* ]] || [[ "$opt" == SNIC* ]] || [[ "$opt" == SMARTPQI* ]] || \
       [[ "$opt" == PM8001* ]] || [[ "$opt" == PMCRAID* ]] || [[ "$opt" == NSP32* ]] || \
       [[ "$opt" == MPI3MR* ]] || [[ "$opt" == LPFC* ]] || [[ "$opt" == LIBFC* ]] || \
       [[ "$opt" == FC_ATTRS* ]] || [[ "$opt" == SAS_* ]] || \
       [[ "$opt" == SRP_* ]] || [[ "$opt" == SPI_ATTRS* ]] || \
       [[ "$opt" == UFS* ]] || [[ "$opt" == ENCLOSURE* ]] || \
       [[ "$opt" == SCSI_DEBUG ]] || [[ "$opt" == SCSI_PROTO_TEST ]] || \
       [[ "$opt" == SCSI_LIB_KUNIT_TEST ]]; then
        return 0
    fi

    # ===== WIRELESS — guests don't need WiFi/Bluetooth =====
    if [[ "$opt" == BT* ]] || [[ "$opt" == WLAN* ]] || [[ "$opt" == MAC80211* ]] || \
       [[ "$opt" == ATH* ]] || [[ "$opt" == IWLW* ]] || [[ "$opt" == RTL8* ]] || \
       [[ "$opt" == RTL* ]] && [[ "$opt" != R8169 ]] || [[ "$opt" == BRCM* ]] && [[ "$opt" != BCM* ]] || \
       [[ "$opt" == CW1200* ]] || [[ "$opt" == ATMEL* ]] || [[ "$opt" == CARL9170* ]] || \
       [[ "$opt" == HERMES* ]] || [[ "$opt" == HOSTAP* ]] || [[ "$opt" == IPW* ]] || \
       [[ "$opt" == MWI37* ]] || [[ "$opt" == PRISM* ]] || [[ "$opt" == SDIO_UART ]] || \
       [[ "$opt" == VIRT_WIFI ]] || [[ "$opt" == CFG80211* ]] || \
       [[ "$opt" == RTW88 ]] || [[ "$opt" == RTW88_* ]] || [[ "$opt" == RTW89 ]] || \
       [[ "$opt" == RTW89_* ]] || [[ "$opt" == WIFI ]] || [[ "$opt" == RFKILL ]] || \
       [[ "$opt" == RFKILL_INPUT ]] || [[ "$opt" == RFKILL_LEDS ]] || \
       [[ "$opt" == RFKILL_GPIO ]] || [[ "$opt" == RFKILL_REGMAP ]]; then
        return 0
    fi

    # ===== REAL NETWORK DRIVERS — use xen-netfront/virtio-net =====
    if [[ "$opt" == 8139CP ]] || [[ "$opt" == 8139TOO ]] || [[ "$opt" == 8139CP* ]] || \
       [[ "$opt" == E100 ]] || [[ "$opt" == E1000 ]] || [[ "$opt" == E1000E ]] || \
       [[ "$opt" == FORGE ]] || [[ "$opt" == HPPA ]] || [[ "$opt" == KS8842 ]] || \
       [[ "$opt" == KS8851 ]] || [[ "$opt" == KS8851_MLL ]] || [[ "$opt" == KS8863 ]] || \
       [[ "$opt" == KSZ884X* ]] || [[ "$opt" == LAN743X ]] || [[ "$opt" == LM7000 ]] || \
       [[ "$opt" == MDIO_THUNDER ]] || [[ "$opt" == Micrel ]] || [[ "$opt" == NATSEMI ]] || \
       [[ "$opt" == NE2K_PCI ]] || [[ "$opt" == NPCM ]] || [[ "$opt" == PCS_XPCS ]] || \
       [[ "$opt" == PHYLINK ]] || [[ "$opt" == PHY_GIGABIT ]] || [[ "$opt" == PHY_FIXED ]] || \
       [[ "$opt" == PHY_BROADCOM ]] || [[ "$opt" == PHY_MICREL ]] || [[ "$opt" == PHY_NATIONAL ]] || \
       [[ "$opt" == PHY_REALTEK ]] || [[ "$opt" == PHY_ATHEROS ]] || [[ "$opt" == PHY_MARVELL ]] || \
       [[ "$opt" == PHY_QSEMI ]] || [[ "$opt" == PHY_MICROCHIP ]] || [[ "$opt" == PHY_DP83848 ]] || \
       [[ "$opt" == PHY_VITESSE ]] || [[ "$opt" == PHY_SMSC ]] || [[ "$opt" == PHY_STE10XP ]] || \
       [[ "$opt" == PHY_TERANETICS ]] || [[ "$opt" == PHY_ICPLUS ]] || [[ "$opt" == PHY_AQUANTIA ]] || \
       [[ "$opt" == PHY_AZALEA ]] || [[ "$opt" == PHY_BCM7XXX ]] || [[ "$opt" == PHY_BCM54140 ]] || \
       [[ "$opt" == PHY_ADIN ]] || [[ "$opt" == PHY_ADMTK ]] || [[ "$opt" == PHY_AKECS ]] || \
       [[ "$opt" == PHY_CICADA ]] || [[ "$opt" == PHY_CONEXANT ]] || [[ "$opt" == PHY_DAVICOM ]] || \
       [[ "$opt" == PHY_ETR ]] || [[ "$opt" == PHY_ETHERNET ]] || [[ "$opt" == PHY_ICPLUS ]] || \
       [[ "$opt" == PHY_KSZ9477 ]] || [[ "$opt" == PHY_LXT ]] || [[ "$opt" == PHY_MICREL_KS8995 ]] || \
       [[ "$opt" == PHY_NATIONAL_DP83822 ]] || [[ "$opt" == PHY_NATIONAL_DP83848 ]] || \
       [[ "$opt" == PHY_NATIONAL_LAN87XX ]] || [[ "$opt" == PHY_QSEMI_QS6612 ]] || \
       [[ "$opt" == PHY_REALTEKRTL8211 ]] || [[ "$opt" == PHY_ROCKCHIP ]] || \
       [[ "$opt" == PHY_SMSC_LAN87XX ]] || [[ "$opt" == PHY_STE10XP ]] || \
       [[ "$opt" == PHY_TERANETICS_TNETV109X ]] || [[ "$opt" == PHY_VITESSE_VSC7385 ]] || \
       [[ "$opt" == PHY_XILINX ]] || [[ "$opt" == PHY_ZTE ]] || \
       [[ "$opt" == PHY_MARVELL_88E1510 ]] || [[ "$opt" == PHY_BROADCOM_BCM54210E ]] || \
       [[ "$opt" == PHY_MICROCHIP_KSZ9031RN ]] || [[ "$opt" == PHY_MICROCHIP_VSC74XX ]] || \
       [[ "$opt" == PHY_NATIONAL_DP83867 ]] || [[ "$opt" == PHY_NATIONAL_DP83TC2112 ]] || \
       [[ "$opt" == PHY_NATIONAL_LAN8742 ]] || [[ "$opt" == PHY_NXP_TJA11XX ]] || \
       [[ "$opt" == PHY_NXP_TJA11XX ]] || [[ "$opt" == PHY_NXP_TJA110X ]] || \
       [[ "$opt" == PHY_REALTEK_RTL8211F ]] || [[ "$opt" == PHY_REALTEK_RTL8211E ]] || \
       [[ "$opt" == PHY_REALTEK_RTL8226 ]] || [[ "$opt" == PHY_ROCKCHIP_RK805 ]] || \
       [[ "$opt" == PHY_ST_STMMAC ]] || [[ "$opt" == PHY_TERANETICS_TNETV109X ]] || \
       [[ "$opt" == PHY_VITESSE_VSC7385 ]] || [[ "$opt" == PHY_XILINX ]] || [[ "$opt" == PHY_ZTE ]] || \
       [[ "$opt" == TUN ]] || [[ "$opt" == TAP ]] || [[ "$opt" == IFB ]] || \
       [[ "$opt" == MACVLAN ]] || [[ "$opt" == MACVTAP ]] || [[ "$opt" == VETH ]] || \
       [[ "$opt" == VRING ]] || [[ "$opt" == VXC ]] || [[ "$opt" == GENEVE ]] || \
       [[ "$opt" == GTP ]] || [[ "$opt" == IPGRE ]] || [[ "$opt" == IP6GRE ]] || \
       [[ "$opt" == IPIP ]] || [[ "$opt" == SIT ]] || [[ "$opt" == IP6TNL ]] || \
       [[ "$opt" == IPV6_SIT ]] || [[ "$opt" == IPV6_TUNNEL ]] || \
       [[ "$opt" == VXLAN ]] || [[ "$opt" == GRE ]] || [[ "$opt" == ERSPAN ]] || \
       [[ "$opt" == GTP ]] || [[ "$opt" == GTPXLATE ]] || [[ "$opt" == HSR ]] || \
       [[ "$opt" == DSA ]] || [[ "$opt" == DSA_TAGGING* ]] || \
       [[ "$opt" == NET_DSA ]] || [[ "$opt" == NET_DSA_* ]] || \
       [[ "$opt" == ALX ]] || [[ "$opt" == ATL* ]] || [[ "$opt" == AX8* ]] || \
       [[ "$opt" == BE2* ]] || [[ "$opt" == BCM* ]] && [[ "$opt" != BCM54140* ]] && [[ "$opt" != BCM7XXX* ]] && [[ "$opt" != BCM_NET_PHYPTP ]] || \
       [[ "$opt" == BNA ]] || [[ "$opt" == BNX* ]] || [[ "$opt" == CB* ]] || \
       [[ "$opt" == CH* ]] || [[ "$opt" == CSI* ]] || [[ "$opt" == DCB ]] || \
       [[ "$opt" == DM9* ]] || [[ "$opt" == DPAA* ]] || [[ "$opt" == E10* ]] || \
       [[ "$opt" == EPIC ]] || [[ "$opt" == FM10* ]] || [[ "$opt" == FSL* ]] || \
       [[ "$opt" == HP1* ]] || [[ "$opt" == HNS* ]] || [[ "$opt" == IGB* ]] || \
       [[ "$opt" == IXGB* ]] || [[ "$opt" == JME ]] || [[ "$opt" == KNA ]] || \
       [[ "$opt" == LAN* ]] || [[ "$opt" == LC* ]] || [[ "$opt" == LCP ]] || \
       [[ "$opt" == LG* ]] || [[ "$opt" == MIC* ]] || [[ "$opt" == MLX* ]] || \
       [[ "$opt" == MV* ]] && [[ "$opt" != MVMEGA* ]] || [[ "$opt" == MYRI* ]] || \
       [[ "$opt" == NA* ]] || [[ "$opt" == NIU ]] || [[ "$opt" == NS* ]] || \
       [[ "$opt" == OC* ]] || [[ "$opt" == PCIX* ]] || [[ "$opt" == PHONET ]] || \
       [[ "$opt" == QLGE ]] || [[ "$opt" == QED* ]] || [[ "$opt" == R6* ]] || \
       [[ "$opt" == RTH* ]] || [[ "$opt" == SB1* ]] || [[ "$opt" == SGI* ]] || \
       [[ "$opt" == SK* ]] || [[ "$opt" == SLS* ]] || [[ "$opt" == SMC* ]] || \
       [[ "$opt" == SPARC* ]] || [[ "$opt" == SR* ]] || [[ "$opt" == STMMAC* ]] || \
       [[ "$opt" == SUN* ]] || [[ "$opt" == SYN* ]] || [[ "$opt" == TIG* ]] || \
       [[ "$opt" == TI* ]] || [[ "$opt" == TLK* ]] || [[ "$opt" == TULIP ]] || \
       [[ "$opt" == UDNIC ]] || [[ "$opt" == VIA* ]] || [[ "$opt" == VIAVELOCITY ]] || \
       [[ "$opt" == VMXNET* ]] || [[ "$opt" == VXGE ]] || [[ "$opt" == WL* ]] || \
       [[ "$opt" == XILINX* ]] || [[ "$opt" == XIRCOM ]] || [[ "$opt" == YEMAMA ]] || \
       [[ "$opt" == NET_VENDOR_* ]] || [[ "$opt" == DUMMY ]] || \
       [[ "$opt" == BONDING ]] || [[ "$opt" == BRIDGE ]] || [[ "$opt" == BRIDGE_* ]] || \
       [[ "$opt" == VLAN_8021Q* ]] || [[ "$opt" == DCB ]] || [[ "$opt" == HSR ]] || \
       [[ "$opt" == CAN ]] || [[ "$opt" == CAN_* ]] || \
       [[ "$opt" == NFC ]] || [[ "$opt" == NFC_* ]] || \
       [[ "$opt" == IEEE802154 ]] || [[ "$opt" == IEEE802154_* ]] || \
       [[ "$opt" == 6LOWPAN* ]] || [[ "$opt" == NETROM ]] || [[ "$opt" == ROSE ]] || \
       [[ "$opt" == AX25 ]] || [[ "$opt" == IPX ]] || [[ "$opt" == ATALK ]] || \
       [[ "$opt" == X25 ]] || [[ "$opt" == LAPB ]] || [[ "$opt" == DECNET ]] || \
       [[ "$opt" == NET_IUCV ]] || [[ "$opt" == NET_CAIF* ]] || [[ "$opt" == NET_9P ]] || \
       [[ "$opt" == PHONET ]] || [[ "$opt" == NFC ]] || [[ "$opt" == NFC_* ]] || \
       [[ "$opt" == IEEE802154 ]] || [[ "$opt" == IEEE802154_* ]] || \
       [[ "$opt" == 6LOWPAN* ]]; then
        return 0
    fi

    # ===== INPUT DEVICES — Xen provides virtual console =====
    if [[ "$opt" == INPUT_MOUSEDEV ]] || [[ "$opt" == INPUT_JOYDEV ]] || \
       [[ "$opt" == INPUT_EVDEV ]] || [[ "$opt" == INPUT_KEYBOARD ]] || \
       [[ "$opt" == INPUT_MOUSE ]] || [[ "$opt" == INPUT_TABLET ]] || \
       [[ "$opt" == INPUT_TOUCHSCREEN ]] || [[ "$opt" == INPUT_MISC ]] || \
       [[ "$opt" == INPUT_SPARSEKMAP ]] || [[ "$opt" == INPUT_MATRIXKMAP ]] || \
       [[ "$opt" == INPUT_LEDS ]] || [[ "$opt" == INPUT_FF_MEMLESS ]] || \
       [[ "$opt" == INPUT_POLLDEV ]] || [[ "$opt" == INPUT_SPARSEKMAP ]] || \
       [[ "$opt" == INPUT_MATRIXKMAP ]] || [[ "$opt" == INPUT_UINPUT ]] || \
       [[ "$opt" == INPUT_XEN_KBDDEV_FRONTEND ]] || \
       [[ "$opt" == KEYBOARD_* ]] || [[ "$opt" == KEYBOARD ]] || \
       [[ "$opt" == MOUSE ]] || [[ "$opt" == MOUSE_* ]] || \
       [[ "$opt" == JOYSTICK ]] || [[ "$opt" == JOYSTICK_* ]] || \
       [[ "$opt" == TOUCHSCREEN ]] || [[ "$opt" == TOUCHSCREEN_* ]] || \
       [[ "$opt" == TABLET ]] || [[ "$opt" == TABLET_* ]] || \
       [[ "$opt" == INPUT_MISC ]] || [[ "$opt" == INPUT_MISC_* ]] || \
       [[ "$opt" == INPUT_GAMEPORT ]] || [[ "$opt" == INPUT_GAMEPORT_* ]] || \
       [[ "$opt" == INPUT_TABLET ]] || [[ "$opt" == INPUT_TABLET_* ]] || \
       [[ "$opt" == INPUT_TOUCHSCREEN ]] || [[ "$opt" == INPUT_TOUCHSCREEN_* ]] || \
       [[ "$opt" == INPUT_MISC ]] || [[ "$opt" == INPUT_MISC_* ]] || \
       [[ "$opt" == INPUT_GAMEPORT ]] || [[ "$opt" == INPUT_GAMEPORT_* ]]; then
        return 0
    fi

    # ===== NON-XEN HYPERVISORS =====
    if [[ "$opt" == KVM* ]] || [[ "$opt" == HYPERV* ]] || [[ "$opt" == ACRN* ]] || \
       [[ "$opt" == VMWARE* ]] || [[ "$opt" == VMCI* ]]; then
        return 0
    fi

    # ===== VSOCK — PV guests use TCP over xen-netfront, no vsock needed =====
    if [[ "$opt" == VSOCKETS ]] || [[ "$opt" == VSOCKETS_* ]] || \
       [[ "$opt" == VIRTIO_VSOCKETS ]] || [[ "$opt" == VHOST_VSOCK ]] || \
       [[ "$opt" == VSOCKMON ]] || [[ "$opt" == HYPERV_VSOCKETS ]] || \
       [[ "$opt" == VMWARE_VMCI_VSOCKETS ]]; then
        return 0
    fi

    # ===== NETFILTER — not needed for waypipe guest =====
    if [[ "$opt" == NETFILTER ]] || [[ "$opt" == NETFILTER_* ]]; then
        return 0
    fi

    # ===== IIO — Industrial I/O, not needed in Xen =====
    if [[ "$opt" == IIO ]] || [[ "$opt" == IIO_* ]] || [[ "$opt" == INDUSTRIALIO ]]; then
        return 0
    fi

    # ===== VIRTIO — no QEMU backend in PV setup, use Xen PV drivers instead =====
    if [[ "$opt" == VIRTIO ]] || [[ "$opt" == VIRTIO_* ]]; then
        return 0
    fi

    # ===== REAL HARDWARE NETWORK — PV guest only uses xen-netfront =====
    if [[ "$opt" == ETHERNET ]] || [[ "$opt" == PHYLIB ]] || [[ "$opt" == MDIO ]] || \
       [[ "$opt" == MDIO_* ]] || [[ "$opt" == PHY_* ]] || [[ "$opt" == WIRELESS ]] || \
       [[ "$opt" == WLAN ]] || [[ "$opt" == CFG80211 ]] || [[ "$opt" == RFKILL ]] || \
       [[ "$opt" == BLUETOOTH ]] || [[ "$opt" == BT ]] || [[ "$opt" == FIREWIRE ]] || \
       [[ "$opt" == IEEE1394 ]] || [[ "$opt" == WAN ]] || [[ "$opt" == PPP ]] || \
       [[ "$opt" == SLIP ]] || [[ "$opt" == ATM ]] || [[ "$opt" == HAMRADIO ]] || \
       [[ "$opt" == PHONE ]] || [[ "$opt" == USB_NET ]] || [[ "$opt" == NET_VENDOR_* ]]; then
        return 0
    fi

    # ===== XEN BACKENDS — guests don't run backends =====
    if [[ "$opt" == XEN_*_BACKEND* ]] || [[ "$opt" == XEN_PCIDEV_BACKEND ]] || \
       [[ "$opt" == XEN_WDT ]] || [[ "$opt" == XEN_FBDEV_FRONTEND ]] || \
       [[ "$opt" == XEN_SCSI_* ]] || [[ "$opt" == XEN_PCIDEV_FRONTEND ]]; then
        return 0
    fi

    # ===== NON-ESSENTIAL FILESYSTEMS =====
    if [[ "$opt" == *_FS ]] || [[ "$opt" == *_FS_* ]] || [[ "$opt" == NLS_* ]]; then
        case "$opt" in
            BTRFS_FS|BTRFS_FS_POSIX_ACL|EXT4_FS|TMPFS|PROC_FS|DEVPTS_FS|AUTOFS_FS|CONFIGFS_FS|SYSFS|DEBUG_FS|RAMFS|SHMEM|EFIVAR_FS|READ_ONLY_THP_FOR_FS|BLK_DEBUG_FS|SCSI_PROC_FS|SND_PROC_FS|USB_CONFIGFS_F_FS|XEN_DEBUG_FS|F2FS_STAT_FS)
                return 1 ;;
            *)
                return 0 ;;
        esac
    fi



    # ===== DEBUG/TRACE — keep essentials =====
    if [[ "$opt" == FTRACE ]] || [[ "$opt" == DYNAMIC_FTRACE ]] || \
       [[ "$opt" == FUNCTION_TRACER ]] || [[ "$opt" == DYNAMIC_DEBUG ]] || \
       [[ "$opt" == LATENCYTOP ]] || [[ "$opt" == MMIOTRACE ]] || \
       [[ "$opt" == RCU_TRACE ]] || [[ "$opt" == BLK_DEV_IO_TRACE ]] || \
       [[ "$opt" == PM_DEBUG ]] || [[ "$opt" == PM_TRACE ]] || \
       [[ "$opt" == DM_DEBUG ]] || [[ "$opt" == ACPI_DEBUG ]] || \
       [[ "$opt" == SLUB_DEBUG ]] || [[ "$opt" == SLUB_STATS ]] || \
       [[ "$opt" == STACKTRACE_BUILD_ID ]] || [[ "$opt" == *_DEBUG ]] || \
       [[ "$opt" == *_TRACE ]] || [[ "$opt" == TEST_* ]] || [[ "$opt" == KUNIT* ]]; then
        return 0
    fi

    # ===== POWER MANAGEMENT EXTRAS =====
    if [[ "$opt" == SUSPEND ]] || [[ "$opt" == HIBERNATE ]] || [[ "$opt" == APM ]] || \
       [[ "$opt" == THERMAL ]] || [[ "$opt" == THERMAL_* ]] || \
       [[ "$opt" == CPU_FREQ_DEFAULT_GOV_* ]] && [[ "$opt" != CPU_FREQ_DEFAULT_GOV_PERFORMANCE ]]; then
        return 0
    fi

    # ===== SECURITY EXTRAS =====
    if [[ "$opt" == SECURITY_TOMOYO ]] || [[ "$opt" == SECURITY_IPE ]] || \
       [[ "$opt" == SECURITY_INFINIBAND ]]; then
        return 0
    fi

    # ===== NVMEM — not needed in Xen =====
    if [[ "$opt" == NVMEM ]] || [[ "$opt" == NVMEM_* ]]; then
        return 0
    fi

    # ===== HARDWARE INTERFACES =====
    if [[ "$opt" == MFD_* ]] || [[ "$opt" == REGULATOR_* ]] || [[ "$opt" == HWMON* ]] || \
       [[ "$opt" == GPIO* ]] || [[ "$opt" == SERIO* ]] || [[ "$opt" == PARPORT* ]] || \
       [[ "$opt" == PATA_* ]] || [[ "$opt" == MMC_* ]] || [[ "$opt" == MEMSTICK* ]] || \
       [[ "$opt" == WIMAX* ]] || [[ "$opt" == IR_* ]] || [[ "$opt" == RC_* ]] || \
       [[ "$opt" == RDMA* ]] || [[ "$opt" == INFINIBAND* ]] || \
       [[ "$opt" == FW_LOADER_USER_HELPER ]] || [[ "$opt" == EDAC* ]] || \
       [[ "$opt" == RAS* ]] || [[ "$opt" == W1_* ]] || [[ "$opt" == W1 ]] || \
       [[ "$opt" == WATCHDOG ]] || [[ "$opt" == *_WDT ]] || \
       [[ "$opt" == BATTERY* ]] || [[ "$opt" == CHARGER* ]] || \
       [[ "$opt" == POWER_SUPPLY ]] || [[ "$opt" == HWMON ]] || \
       [[ "$opt" == SENSORS_* ]] || [[ "$opt" == HID_* ]] || \
       [[ "$opt" == PINCTRL_* ]] || [[ "$opt" == RTC_DRV_* ]] || \
       [[ "$opt" == CROS_EC* ]] || \
       [[ "$opt" == TYPEC ]] || [[ "$opt" == TYPEC_* ]] || \
       [[ "$opt" == NTB ]] || [[ "$opt" == NTB_* ]] || \
       [[ "$opt" == AD* ]] || [[ "$opt" == ABP* ]] || [[ "$opt" == ACER* ]] || \
       [[ "$opt" == ALS_* ]] || [[ "$opt" == AXP20X_* ]] || \
       [[ "$opt" == ACPI_APEI* ]] || [[ "$opt" == ACPI_NFIT ]] || [[ "$opt" == ACPI_PFRUT ]] || \
       [[ "$opt" == ACPI_SBS ]] || [[ "$opt" == ACPI_TAD ]] || [[ "$opt" == ACPI_TOSHIBA ]] || \
       [[ "$opt" == ACPI_VIDEO ]] || [[ "$opt" == ACPI_WMI* ]] || [[ "$opt" == ACPI_QUICKSTART ]] || \
       [[ "$opt" == ACPI_PROCESSOR_AGGREGATOR ]] || [[ "$opt" == ACPI_IPMI ]] || \
       [[ "$opt" == ACPI_ALS ]] || [[ "$opt" == ACPI_EXTLOG ]] || \
       [[ "$opt" == BRIDGE_EBT* ]] || \
       [[ "$opt" == MEI* ]] || [[ "$opt" == THUNDERBOLT ]] || [[ "$opt" == USB4 ]] || \
       [[ "$opt" == IIO_* ]] || [[ "$opt" == INDUSTRIALIO ]] || \
       [[ "$opt" == SOUNDWIRE ]] || [[ "$opt" == SOUNDWIRE_* ]] || \
       [[ "$opt" == DSP_* ]] || [[ "$opt" == SND_SOC ]] || \
       [[ "$opt" == FRAMEBUFFER ]] || \
       [[ "$opt" == STAGING ]] || [[ "$opt" == STAGING_* ]] || \
       [[ "$opt" == REMOTEPROC ]] || [[ "$opt" == REMOTEPROC_* ]] || \
       [[ "$opt" == RPMSG ]] || [[ "$opt" == RPMSG_* ]] || \
       [[ "$opt" == VIRTIO_INPUT ]] || [[ "$opt" == VIRTIO_MMIO ]] || \
       [[ "$opt" == VIRTIO_RTC ]] || [[ "$opt" == VIRTIO_VDPA ]] || \
       [[ "$opt" == VIRTIO_VFIO ]] || [[ "$opt" == VIRTIO_FS ]] || \
       [[ "$opt" == VIRTIO_MEM ]] || [[ "$opt" == VIRTIO_IOMMU ]] || \
       [[ "$opt" == VIRTIO_PCI_LEGACY ]] || \
       [[ "$opt" == BCMA ]] || [[ "$opt" == CFG80211 ]] || [[ "$opt" == WLAN ]] || \
       [[ "$opt" == WLAN_VENDOR_* ]] || [[ "$opt" == ATH* ]] || [[ "$opt" == IWLW* ]] || \
       [[ "$opt" == RTL8* ]] || [[ "$opt" == BRCM* ]] || [[ "$opt" == CW1200* ]] || \
       [[ "$opt" == ATMEL* ]] || [[ "$opt" == CARL9170* ]] || [[ "$opt" == HERMES* ]] || \
       [[ "$opt" == HOSTAP* ]] || [[ "$opt" == IPW* ]] || [[ "$opt" == MWI37* ]] || \
       [[ "$opt" == PRISM* ]] || [[ "$opt" == SDIO_UART ]] || [[ "$opt" == VIRT_WIFI ]] || \
       [[ "$opt" == VMXNET3 ]] || [[ "$opt" == NETDEVSIM ]] || \
       [[ "$opt" == GPIB ]] || [[ "$opt" == GPIB_* ]] || \
       [[ "$opt" == MTD ]] || [[ "$opt" == MTD_* ]] || \
       [[ "$opt" == FIREWIRE ]] || [[ "$opt" == FIREWIRE_* ]] || \
       [[ "$opt" == IEEE1394 ]] || [[ "$opt" == IEEE1394_* ]] || \
       [[ "$opt" == OHCI1394 ]] || [[ "$opt" == SBP2 ]] || \
       [[ "$opt" == SERIAL_* ]] && [[ "$opt" != SERIAL_8250 ]] && \
       [[ "$opt" != SERIAL_8250_CONSOLE ]] && [[ "$opt" != SERIAL_8250_DMA ]] && \
       [[ "$opt" != SERIAL_8250_FSL ]] && [[ "$opt" != SERIAL_AMBA_PL011 ]] && \
       [[ "$opt" != SERIAL_CORE ]] && [[ "$opt" != SERIAL_EARLYCON ]] && \
       [[ "$opt" != SERIAL_EARLYCON8250 ]] && [[ "$opt" != SERIAL_MULTI_INSTANTIATE ]] || \
       [[ "$opt" == SPEAKUP ]] || [[ "$opt" == SPEAKUP_* ]] || \
       [[ "$opt" == RADIO ]] || [[ "$opt" == RADIO_* ]] || \
       [[ "$opt" == SOUND ]] || [[ "$opt" == SND ]] || \
       [[ "$opt" == BLK_DEV_* ]] && [[ "$opt" != BLK_DEV_LOOP ]] && \
       [[ "$opt" != BLK_DEV_RAM ]] && [[ "$opt" != BLK_DEV_NBD ]] && \
       [[ "$opt" != BLK_DEV_INITRD ]] && [[ "$opt" != BLK_DEV_DM ]] && \
       [[ "$opt" != BLK_DEV_MD ]] && [[ "$opt" != BLK_DEV_BSGLIB ]] && \
       [[ "$opt" != BLK_DEV_INTEGRITY ]] && [[ "$opt" != BLK_DEV_LOOP_MIN_COUNT ]] && \
       [[ "$opt" != BLK_DEV_RAM_COUNT ]] && [[ "$opt" != BLK_DEV_RAM_SIZE ]] || \
       [[ "$opt" == I2C ]] || [[ "$opt" == I2C_* ]] || \
       [[ "$opt" == SPI ]] || [[ "$opt" == SPI_* ]] || \
       [[ "$opt" == PTP_1588_CLOCK ]] || [[ "$opt" == PTP_1588_CLOCK_* ]] || \
       [[ "$opt" == VDPA_SIM_NET ]] || [[ "$opt" == OCTEONEP_VDPA ]] || \
       [[ "$opt" == VHOST_NET ]] || \
       [[ "$opt" == BLK_DEV_PMEM ]] || \
       [[ "$opt" == INTEL_TH* ]] || [[ "$opt" == XILINX_PR_DECOUPLER ]] || \
       [[ "$opt" == INTEL_QEP ]]; then
        return 0
    fi

    # ===== THERMAL — Xen handles thermal in dom0 =====
    if [[ "$opt" == THERMAL ]] || [[ "$opt" == THERMAL_* ]] || \
       [[ "$opt" == INT340X_* ]] || [[ "$opt" == X86_PKG_TEMP_THERMAL ]] || \
       [[ "$opt" == INTEL_SOC_DTS_IOSF ]] || [[ "$opt" == ACPI_THERMAL_REL ]]; then
        return 0
    fi

    # ===== NVME — PV guest uses xen-blkfront =====
    if [[ "$opt" == NVME ]] || [[ "$opt" == NVME_* ]]; then
        return 0
    fi

    # ===== SCSI TRANSPORTS — PV guest uses xen-blkfront =====
    if [[ "$opt" == SCSI_TRANSPORT_* ]] || [[ "$opt" == SCSI_DH_* ]] || \
       [[ "$opt" == RAID_CLASS ]]; then
        return 0
    fi

    # ===== TCP CONGESTION — keep cubic (built-in) + bbr only =====
    if [[ "$opt" == TCP_* ]] && [[ "$opt" != TCP_BBR ]] && \
       [[ "$opt" != TCP_CONGESTION ]] && [[ "$opt" != TCP_MD5SIG ]] && \
       [[ "$opt" != TCP_FACK ]] && [[ "$opt" != TCP_SACK ]] && \
       [[ "$opt" != TCP_TIMESTAMPS ]] && [[ "$opt" != TCP_ECN ]] && \
       [[ "$opt" != TCP_RFC1337 ]] && [[ "$opt" != TCP_ADV_WIN_SCALING ]]; then
        return 0
    fi

    # ===== MISC DRIVERS — keep pvpanic, tpm, hangcheck-timer =====
    if [[ "$opt" == EEPROM ]] || [[ "$opt" == EEPROM_* ]] || \
       [[ "$opt" == CARDREADER ]] || [[ "$opt" == CARDREADER_* ]] || \
       [[ "$opt" == UACCE ]] || [[ "$opt" == RPMB ]] || \
       [[ "$opt" == NTSYNC ]] || [[ "$opt" == ISL29020 ]] || [[ "$opt" == ISL29003 ]] || \
       [[ "$opt" == IBMASM ]] || [[ "$opt" == HP_ILO ]] || \
       [[ "$opt" == DW_XDATA_PCIE ]] || [[ "$opt" == APDS9802ALS ]] || \
       [[ "$opt" == ALTERA_STAPL ]] || [[ "$opt" == MCHP_PCI1XXXX ]] || \
       [[ "$opt" == XILLYBUS ]] || [[ "$opt" == UV_MMtimer ]] || \
       [[ "$opt" == TLCLK ]] || [[ "$opt" == IPMI ]] || [[ "$opt" == IPMI_* ]]; then
        return 0
    fi

    # ===== HW_RANDOM — keep only virtio-rng (not available) and core =====
    if [[ "$opt" == HW_RANDOM ]] || [[ "$opt" == HW_RANDOM_* ]]; then
        case "$opt" in
            HW_RANDOM_CORE|HW_RANDOM_TIMERIOT) return 1 ;;
            *) return 0 ;;
        esac
    fi

    # ===== X86 PLATFORM DEVICES — laptop/vendor specific, not needed in Xen =====
    if [[ "$opt" == X86_PLATFORM_DEVICES ]] || [[ "$opt" == X86_ANDROID_TABLETS ]] || \
       [[ "$opt" == X86_INTEL_PUNIT_IPC ]] || [[ "$opt" == X86_PKG_tempThr ]] || \
       [[ "$opt" == ACPI_WMI ]] || [[ "$opt" == ACPI_TOSHIBA ]] || \
       [[ "$opt" == ASUS_LAPTOP ]] || [[ "$opt" == ASUS_WIRELESS ]] || \
       [[ "$opt" == DELL_LAPTOP ]] || [[ "$opt" == FUJITSU_LAPTOP ]] || \
       [[ "$opt" == GPD_POCKET_FAN ]] || [[ "$opt" == EEPC_LAPTOP ]] || \
       [[ "$opt" == THINKPAD_ACPI ]] || [[ "$opt" == TOSHIBA_BTC ]] || \
       [[ "$opt" == TOSHIBA_HAPS ]] || [[ "$opt" == TOSHIBA_WMI ]] || \
       [[ "$opt" == MSI_WMI ]] || [[ "$opt" == PANASONIC_LAPTOP ]] || \
       [[ "$opt" == SONY_LAPTOP ]] || [[ "$opt" == COMPAQ_LAPTOP ]] || \
       [[ "$opt" == HP_WMI ]] || [[ "$opt" == HP_ACCEL ]] || \
       [[ "$opt" == INSPIRON_LAPTOP ]] || [[ "$opt" == IBM_RTL ]] || \
       [[ "$opt" == JMICRON_ROBOTRAM ]] || [[ "$opt" == APPLE_GMUX ]] || \
       [[ "$opt" == CHROMEOS_LAPTOP ]] || [[ "$opt" == CHROMEOS_PSTORE ]] || \
       [[ "$opt" == SURFACE3_BUTTON ]] || [[ "$opt" == SURFACE_AGgregator ]] || \
       [[ "$opt" == SURFACE_BUTTON ]] || [[ "$opt" == SURFACE_PRO3 ]] || \
       [[ "$opt" == INTEL_OPS ]] || [[ "$opt" == INTEL_SCU ]] || \
       [[ "$opt" == INTEL_SCU_IPC ]] || [[ "$opt" == INTEL_SCU_UTIL ]] || \
       [[ "$opt" == INTEL_SPEED_SELECT_INTERFACE ]]; then
        return 0
    fi

    # ===== CPU VENDOR-SPECIFIC =====
    if [[ "$opt" == INTEL_* ]] && [[ "$opt" != INTEL_IOMMU ]] && [[ "$opt" != INTEL_IOMMU_SVM ]] && \
       [[ "$opt" != INTEL_IOMMU_SCALABLE_MODE_DEFAULT_ON ]] && \
       [[ "$opt" != INTEL_IOMMU_PERF_EVENTS ]] && [[ "$opt" != INTEL_IDLE ]] && \
       [[ "$opt" != INTEL_CSTATE ]] && [[ "$opt" != INTEL_RAPL ]] && \
       [[ "$opt" != INTEL_RDT* ]] && [[ "$opt" != INTEL_THERMAL ]] && \
       [[ "$opt" != INTEL_HFI ]] && [[ "$opt" != INTEL_PMC_CORE ]] && \
       [[ "$opt" != INTEL_VSEC ]] && [[ "$opt" != INTEL_IMC ]] && \
       [[ "$opt" != INTEL_MENLOW ]] && [[ "$opt" != INTEL_PMC_* ]] && \
       [[ "$opt" != INTEL_SPEED_SELECT_INTERFACE ]] && [[ "$opt" != INTEL_IPS ]] && \
       [[ "$opt" != INTEL_SCU_* ]] && [[ "$opt" != INTEL_RST ]] && \
       [[ "$opt" != INTEL_SMARTCONNECT ]] && [[ "$opt" != INTEL_TPMI ]] && \
       [[ "$opt" != INTEL_TURBO_MAX_3 ]] && [[ "$opt" != INTEL_MEI ]] && \
       [[ "$opt" != INTEL_MEI_ME ]] && [[ "$opt" != INTEL_MEI_TXE ]] && \
       [[ "$opt" != INTEL_MEI_CSC ]]; then
        return 0
    fi
    if [[ "$opt" == AMD_* ]] && [[ "$opt" != AMD_IOMMU ]] && [[ "$opt" != AMD_IOMMU_IOMMUFD ]] && \
       [[ "$opt" != AMD_MEM_ENCRYPT ]] && [[ "$opt" != AMD_PSTATE ]] && \
       [[ "$opt" != AMD_PMC ]] && [[ "$opt" != AMD_RAPL ]] && \
       [[ "$opt" != AMD_VIRT ]] && [[ "$opt" != AMDVI* ]] && \
       [[ "$opt" != AMD_MP2_STB ]] && [[ "$opt" != AMD_HFI ]] && \
       [[ "$opt" != AMD_3D_VCACHE ]] && [[ "$opt" != AMD_WBRF ]]; then
        return 0
    fi

    # ===== NETWORK SCHEDULING/ACTIONS =====
    if [[ "$opt" == NET_SCH_* ]] && [[ "$opt" != NET_SCH_FIFO ]] && \
       [[ "$opt" != NET_SCH_PRIO ]] && [[ "$opt" != NET_SCH_RED ]] && \
       [[ "$opt" != NET_SCH_SFQ ]] && [[ "$opt" != NET_SCH_TBF ]]; then
        return 0
    fi
    if [[ "$opt" == NET_ACT_* ]] && [[ "$opt" != NET_ACT_GACT ]] && \
       [[ "$opt" != NET_ACT_MIRRED ]] && [[ "$opt" != NET_ACT_POLICE ]]; then
        return 0
    fi
    if [[ "$opt" == NET_EMATCH_* ]] || [[ "$opt" == NET_CLS_* ]] && \
       [[ "$opt" != NET_CLS_ACT ]] && [[ "$opt" != NET_CLS_BASIC ]] && \
       [[ "$opt" != NET_CLS_BPF ]] && [[ "$opt" != NET_CLS_CGROUP ]] && \
       [[ "$opt" != NET_CLS_FLOW ]] && [[ "$opt" != NET_CLS_FLOWER ]] && \
       [[ "$opt" != NET_CLS_FW ]] && [[ "$opt" != NET_CLS_MATCHALL ]] && \
       [[ "$opt" != NET_CLS_ROUTE4 ]] && [[ "$opt" != NET_CLS_U32 ]]; then
        return 0
    fi

    return 1
}

{
while IFS= read -r line || [ -n "$line" ]; do
    if [[ -z "$line" ]] || [[ "$line" =~ ^#\s*#.* ]]; then
        echo "$line"
        continue
    fi
    if [[ "$line" =~ ^# ]]; then
        echo "$line"
        continue
    fi
    if [[ "$line" =~ ^CONFIG_(.+)= ]]; then
        opt="${line#CONFIG_}"
        opt="${opt%%=*}"
        if should_disable "$opt"; then
            echo "# CONFIG_${opt} is not set"
            continue
        fi
        echo "$line"
    else
        echo "$line"
    fi
done < "$INPUT"

# Force required options — remove any existing entries first (kernel config
# keeps the FIRST value for duplicates, so we must remove conflicting lines)
for opt in XEN_NETDEV_FRONTEND XEN_BLKDEV_FRONTEND XEN_CONSOLE_FRONTEND \
           BTRFS_FS EXT4_FS XFS_FS DEBUG_FS KALLSYMS SECURITY_SELINUX AUDIT \
           IMA EVM INTEGRITY PM CPU_FREQ CPU_IDLE EFI EFI_STUB \
           XEN XEN_PV XEN_PVHVM XEN_PVH HYPERVISOR_GUEST TIMERFD \
           BTRFS_FS_POSIX_ACL OVERLAY_FS \
           DM DM_INIT DM_UEVENT DM_SNAPSHOT DM_ZERO DM_VERITY MD \
           NAMESPACES UTS_NS IPC_NS PID_NS NET_NS USER_NS CGROUP_NS TIME_NS \
           BLK_DEV_ZONED BLK_CGROUP BLK_DEV_THROTTLING; do
    sed -i "/^CONFIG_${opt}=/d; /^# CONFIG_${opt} is not set/d" "$OUTPUT"
done

# Minimal Xen PV guest kernel overrides (no conflicts — clean slate)
cat >> "$OUTPUT" <<'EOF'

# Minimal Xen PV guest kernel overrides (pi agent VM — no ostree root)
CONFIG_XEN_NETDEV_FRONTEND=y
CONFIG_XEN_BLKDEV_FRONTEND=y
CONFIG_XEN_CONSOLE_FRONTEND=y
# Workspace-disk filesystem (no ostree/BTRFS/OVERLAY/DM)
CONFIG_EXT4_FS=y
# 9p (trans=xen) built-in — the pi agent's seed/workspace share
CONFIG_NET_9P=y
CONFIG_NET_9P_XEN=y
CONFIG_NETFS_SUPPORT=y
CONFIG_9P_FS=y
CONFIG_DEBUG_FS=y
# Monolithic — no module loading (only what's required for Xen hardware)
CONFIG_MODULES=n
CONFIG_KALLSYMS=y
CONFIG_SECURITY_SELINUX=y
CONFIG_AUDIT=y
CONFIG_IMA=y
CONFIG_EVM=y
CONFIG_INTEGRITY=y
CONFIG_PM=y
CONFIG_CPU_FREQ=y
CONFIG_CPU_IDLE=y
CONFIG_EFI=y
CONFIG_EFI_STUB=y
CONFIG_PARAVIRT=y
CONFIG_XEN=y
CONFIG_XEN_PV=y
CONFIG_XEN_PVHVM=y
CONFIG_XEN_PVH=y
CONFIG_HYPERVISOR_GUEST=y
CONFIG_TIMERFD=y
CONFIG_NAMESPACES=y
CONFIG_UTS_NS=y
CONFIG_IPC_NS=y
CONFIG_PID_NS=y
CONFIG_NET_NS=y
CONFIG_USER_NS=y
CONFIG_CGROUP_NS=y
CONFIG_TIME_NS=y
CONFIG_BLK_DEV_ZONED=y
CONFIG_BLK_CGROUP=y
CONFIG_BLK_DEV_THROTTLING=y

# Disable parent categories that pull in unnecessary modules
# (explicit =n required — default y options are re-enabled otherwise)
CONFIG_NETFILTER=n
CONFIG_NETFILTER_ADVANCED=n
CONFIG_IIO=n
CONFIG_INDUSTRIALIO=n
# Keep CONFIG_MD=y — required for device-mapper (ostree root)
# CONFIG_MD=n
# CONFIG_BLK_DEV_MD=n
CONFIG_THERMAL=n
CONFIG_USB=n
CONFIG_MMC=n
CONFIG_NVMEM=n
CONFIG_PWM=n
CONFIG_HWMON=n
CONFIG_POWER_SUPPLY=n
CONFIG_WATCHDOG=n
CONFIG_RAS=n
CONFIG_EDAC=n
CONFIG_FPGA=n
CONFIG_VHOST=n
CONFIG_VDPA=n
CONFIG_VFIO=n
CONFIG_TARGET_CORE=n
CONFIG_NVME_CORE=n

# Real hardware — PV guest has no real hardware
CONFIG_ETHERNET=n
CONFIG_PHYLIB=n
CONFIG_MDIO=n
CONFIG_X86_PLATFORM_DEVICES=n
CONFIG_WIRELESS=n
CONFIG_WLAN=n
CONFIG_CFG80211=n
CONFIG_RFKILL=n
CONFIG_BLUETOOTH=n
CONFIG_BT=n
CONFIG_FIREWIRE=n
CONFIG_IEEE1394=n
CONFIG_MTD=n
CONFIG_PARPORT=n
CONFIG_PNP=n
CONFIG_SERIO=n
CONFIG_HID=n
CONFIG_INPUT=n
CONFIG_XEN_PCIDEV_FRONTEND=n
CONFIG_VIRTIO_PCI=n
CONFIG_STAGING=n
CONFIG_USB_NET=n
CONFIG_WAN=n
CONFIG_PHONE=n
CONFIG_PPP=n
CONFIG_SLIP=n
CONFIG_ATM=n
CONFIG_HAMRADIO=n

# Options the kernel config system sets via dependency resolution
# (must be explicitly set to avoid spec validation errors)
CONFIG_KCMP=n
CONFIG_SERIAL_8250_NR_UARTS=4
CONFIG_SERIAL_8250_RUNTIME_UARTS=4
CONFIG_INTEL_PMT_DISCOVERY=n
CONFIG_NLS_DEFAULT="iso8859-1"
CONFIG_MSEAL_SYSTEM_MAPPINGS=n
CONFIG_IRQ_POLL=n
CONFIG_DYNAMIC_DEBUG_CORE=n
CONFIG_MICROCODE=y
CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y
CONFIG_SYN_COOKIES=y
CONFIG_IPV6_TUNNEL=m
CONFIG_FAILOVER=y
CONFIG_NET_FAILOVER=y
CONFIG_SERIAL_CORE_CONSOLE=y
CONFIG_SUNRPC=m
CONFIG_SUNRPC_GSS=m
CONFIG_NLS_UCS2_UTILS=m
CONFIG_DEBUG_FS_ALLOW_ALL=y
EOF
} > "$OUTPUT"
