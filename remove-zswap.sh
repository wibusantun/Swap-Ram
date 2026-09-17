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

if [[ $EUID -ne 0 ]]; then
    print_error "Script ini harus dijalankan sebagai root!"
fi

SWAP_FILE="/swapfile"

echo -e "${YELLOW}Memulai proses pembersihan Swap dan ZRAM...${NC}"

# Hapus ZRAM
if dpkg -l | grep -q "zram-tools"; then
    print_info "Mencabut ZRAM..."
    apt-get remove --purge zram-tools -y > /dev/null 2>&1
    print_success "ZRAM dihapus sepenuhnya."
else
    print_info "ZRAM tidak ditemukan."
fi

# Hapus Disk Swap
print_info "Mencabut Disk Swap..."
if swapon --show | grep -q "$SWAP_FILE"; then
    swapoff $SWAP_FILE
    print_success "Disk Swap dinonaktifkan."
fi

if [[ -f "$SWAP_FILE" ]]; then
    rm -f $SWAP_FILE
    print_success "File $SWAP_FILE dihapus."
fi

# Bersihkan fstab secara presisi di awal baris
sed -i "\|^$SWAP_FILE|d" /etc/fstab
print_success "Entri Disk Swap dihapus dari /etc/fstab secara bersih."

echo -e "${PURPLE}\n[ Sistem kembali ke pengaturan awal tanpa Swap ]\n${NC}"
