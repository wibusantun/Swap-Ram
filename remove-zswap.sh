#!/bin/bash

export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export NC='\033[0m'

print_info() { echo -e "${BLUE}➽ $1${NC}"; }
print_success() { echo -e "${GREEN}✔ $1${NC}"; }
print_error() { echo -e "${RED}✘ $1${NC}"; exit 1; }

if [[ $EUID -ne 0 ]]; then print_error "Script ini harus dijalankan sebagai root!"; fi

SWAP_FILE="/swapfile"

echo -e "${YELLOW}Memulai proses pembersihan Total (Disk Swap, ZRAM, & ZSWAP)...${NC}"
echo ""

# 1. Cabut ZRAM (Jika terinstal)
if dpkg -l | grep -q "zram-tools"; then
    print_info "Mencabut ZRAM..."
    systemctl stop zramswap > /dev/null 2>&1
    apt-get remove --purge zram-tools -y > /dev/null 2>&1
    print_success "ZRAM dihapus sepenuhnya."
else
    print_info "ZRAM tidak ditemukan di sistem."
fi

# 2. Cabut Disk Swap
print_info "Mencabut Disk Swap..."
if swapon --show | grep -q "$SWAP_FILE"; then
    sync; echo 3 > /proc/sys/vm/drop_caches # Amankan RAM sebelum mematikan swap
    swapoff $SWAP_FILE
    print_success "Disk Swap dinonaktifkan."
fi

if [[ -f "$SWAP_FILE" ]]; then
    rm -f $SWAP_FILE
    print_success "File $SWAP_FILE dihapus."
fi

# 3. Bersihkan /etc/fstab
sed -i "\|^$SWAP_FILE|d" /etc/fstab
print_success "Entri Disk Swap dihapus dari /etc/fstab secara bersih."

# 4. Cabut ZSWAP dari GRUB & Initramfs
if [[ -f /etc/default/grub ]]; then
    print_info "Membersihkan parameter ZSWAP dari GRUB..."
    # Hapus semua string berawalan zswap. dari parameter boot menggunakan regex
    sed -i -E 's/zswap\.([a-zA-Z_]+=[^ ]+ *)//g' /etc/default/grub
    update-grub > /dev/null 2>&1
    print_success "Konfigurasi ZSWAP dihapus dari bootloader."
    
    # Bersihkan injeksi modul dari Initramfs
    if [[ -f /etc/initramfs-tools/modules ]]; then
        print_info "Membersihkan injeksi modul ZSWAP dari Initramfs..."
        sed -i '/^lz4$/d' /etc/initramfs-tools/modules
        sed -i '/^lz4_compress$/d' /etc/initramfs-tools/modules
        sed -i '/^z3fold$/d' /etc/initramfs-tools/modules
        
        # Build ulang agar modul benar-benar tercabut dari boot image
        update-initramfs -u > /dev/null 2>&1
        print_success "Modul kompresi (lz4 & z3fold) dihapus dari early-boot."
    fi
    
    print_info "Perubahan kernel akan terasa setelah reboot selanjutnya."
fi

echo -e "${PURPLE}\n[ ✓ Sistem telah dikembalikan ke pengaturan awal tanpa Swap ]\n${NC}"