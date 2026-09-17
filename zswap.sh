#!/bin/bash

# Instalasi Swap (ZRAM + Disk Swap)
# Membutuhkan OS Debian/Ubuntu. Pastikan dijalankan sebagai root.

export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export LIGHT='\033[0;37m'
export NC='\033[0m'

get_os_info() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME="$PRETTY_NAME"
    else
        OS_NAME="Unknown"
    fi
    echo "$OS_NAME"
}

display_info() {
    clear
    echo -e "${YELLOW}┌─────────────────${NC} ${LIGHT}◈ Swap Installer ◈${NC} ${YELLOW}─────────────────┐${NC}"
    echo -e "${YELLOW} ➽ OS      : $(get_os_info) ${NC}"
    echo -e "${YELLOW} ➽ RAM     : $(free -m | awk '/^Mem:/{print $2}') MB ${NC}"
    echo -e "${YELLOW}└──────────────────────────────────────────────────────┘${NC}"
    echo -e "${CYAN} Konfigurasi: ZRAM + Disk Swap ${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_info() { echo -e "${BLUE}➽ $1${NC}"; }
print_success() { echo -e "${GREEN}✔ $1${NC}"; }
print_error() { echo -e "${RED}✘ $1${NC}"; exit 1; }

if [[ $EUID -ne 0 ]]; then
    print_error "Script ini harus dijalankan sebagai root!"
fi

if ! command -v apt &> /dev/null; then
    print_error "Script ini khusus untuk Debian/Ubuntu. Package manager 'apt' tidak ditemukan."
fi

SWAP_FILE="/swapfile"

display_info

# Install ZRAM
print_info "Tahap 1: Menginstal dan Mengonfigurasi ZRAM..."
apt-get update -y > /dev/null 2>&1
apt-get install zram-tools -y > /dev/null 2>&1

cat <<EOF > /etc/default/zramswap
ALGO=lz4
PERCENT=50
PRIORITY=100
EOF

systemctl restart zramswap
print_success "ZRAM berhasil diaktifkan "

# DISK SWAP
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
print_info "Tahap 2: Pembuatan Swap Disk"
while true; do
    echo -n -e "${YELLOW}Masukkan ukuran Disk Swap (dalam GB, misal: 1 atau 2): ${NC}"
    read SWAP_SIZE_GB
    if [[ $SWAP_SIZE_GB =~ ^[0-9]+$ && $SWAP_SIZE_GB -gt 0 ]]; then
        break
    else
        echo -e "${RED}✘ Input tidak valid! Masukkan angka positif.${NC}"
    fi
done

if swapon --show | grep -q "$SWAP_FILE"; then
    print_info "Menghapus swap lama secara bersih..."
    swapoff $SWAP_FILE
    rm -f $SWAP_FILE
    sed -i "\|^$SWAP_FILE|d" /etc/fstab
fi

print_info "Membuat Swap Disk sebesar ${SWAP_SIZE_GB}GB ..."
# Fallocate dihapus karena menyebabkan sparse files pada beberapa filesystem VPS yang membunuh performa I/O.
dd if=/dev/zero of=$SWAP_FILE bs=1M count=$((SWAP_SIZE_GB * 1024)) status=progress
chmod 600 $SWAP_FILE
mkswap $SWAP_FILE > /dev/null 2>&1
swapon -p 10 $SWAP_FILE
print_success "Disk Swap siap dengan prioritas 10"

# Tambahkan ke fstab
if ! grep -q "^$SWAP_FILE" /etc/fstab; then
    echo "$SWAP_FILE none swap sw,pri=10 0 0" >> /etc/fstab
fi

echo -e "${PURPLE}\n[ Instalasi Tiered Swap Selesai ]\n${NC}"
echo -e "${YELLOW}Hasil akhir sistem memori virtual Anda:${NC}"
swapon --show
