#!/bin/sh

make mrproper
make sama5_cmp_defconfig
make uImage -j16

make sama5d36ek.dtb
make sama5d36ek_pda4.dtb
make sama5d36ek_pda7.dtb
make sama5d36ek_revc.dtb
make sama5d36ek_revc_pda4.dtb
make sama5d36ek_revc_pda7.dtb

make sama5d36ek_audio.dtb
make sama5d36ek_dhrystone.dtb
make sama5d36ek_gmac.dtb
make sama5d36ek_isi.dtb
make sama5d36ek_pda4_isi.dtb
make sama5d36ek_pda7_isi.dtb
make sama5d36ek_lcd.dtb
make sama5d36ek_pda4_lcd.dtb
make sama5d36ek_pda7_lcd.dtb
make sama5d36ek_pm.dtb
make sama5d36ek_revc_audio.dtb
make sama5d36ek_revc_isi.dtb
make sama5d36ek_revc_pda4_isi.dtb
make sama5d36ek_revc_pda7_isi.dtb
make sama5d36ek_usb.dtb


cd arch/arm/boot/dts

export PATH=$PATH:../../../../scripts/dtc/
mkimage -f sama5d36ek_cmp.its sama5d36ek_cmp.itb 
