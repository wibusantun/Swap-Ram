#!/bin/bash

# ====================================================================
# Smart Tiered Swap Installer (Auto-detect ZSWAP / ZRAM + Disk Swap)
# OS Support: Debian & Ubuntu
# ====================================================================

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
        echo "$PRETTY_NAME"
    else
        echo "Unknown Linux"
    fi
}

# Deteksi tipe virtualisasi
VIRT_TYPE=$(systemd-detect-virt 2>/dev/null || echo "unknown")

display_info() {
    clear
    echo -e "${YELLOW}┌─────────────────${NC} ${LIGHT}◈ Smart Swap Installer ◈${NC} ${YELLOW}─────────────────┐${NC}"
    echo -e "${YELLOW} ➽ OS        : $(get_os_info) ${NC}"
    echo -e "${YELLOW} ➽ RAM       : $(free -m | awk '/^Mem:/{print $2}') MB ${NC}"
    echo -e "${YELLOW} ➽ Disk Free : $(df -h / | awk 'NR==2 {print $4}') ${NC}"
    echo -e "${YELLOW} ➽ Virt Type : ${VIRT_TYPE^^} ${NC}"
    echo -e "${YELLOW}└─────────────────────────────────────────────────────────────┘${NC}"
}

print_info() { echo -e "${BLUE}➽ $1${NC}"; }
print_success() { echo -e "${GREEN}✔ $1${NC}"; }
print_error() { echo -e "${RED}✘ $1${NC}"; exit 1; }

if [[ $EUID -ne 0 ]]; then print_error "Script ini harus dijalankan sebagai root!"; fi
if ! command -v apt &> /dev/null; then print_error "Script ini khusus Debian/Ubuntu."; fi

SWAP_FILE="/swapfile"
display_info

# ==========================================
# DETEKSI MODE: ZSWAP ATAU ZRAM
# ==========================================
MODE="ZRAM"
if [[ "$VIRT_TYPE" == "kvm" || "$VIRT_TYPE" == "qemu" || "$VIRT_TYPE" == "vmware" ]]; then
    if [[ -f /etc/default/grub ]]; then
        MODE="ZSWAP"
    fi
fi

echo -e "${CYAN} Konfigurasi Terpilih: ${MODE} + Disk Swap ${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# ==========================================
# TAHAP 1: DISK SWAP
# ==========================================
print_info "Tahap 1: Pembuatan Swap Disk"
FREE_DISK_GB=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')

while true; do
    echo -n -e "${YELLOW}Masukkan ukuran Disk Swap (GB) [Sisa Disk: ${FREE_DISK_GB}GB]: ${NC}"
    
    SWAP_SIZE_GB=""
    read -r SWAP_SIZE_GB < /dev/tty || true
    
    if [ -z "$SWAP_SIZE_GB" ]; then
        echo -e "\n${RED}✘ Terminal tidak interaktif. Eksekusi pipe gagal membaca input.${NC}"
        echo -e "${YELLOW}Silakan jalankan script dengan cara mendownloadnya terlebih dahulu:${NC}"
        echo -e "${LIGHT}wget https://raw.githubusercontent.com/wibusantun/Swap-Ram/main/zswap.sh${NC}"
        echo -e "${LIGHT}bash zswap.sh${NC}"
        exit 1
    fi
    
    # Hapus spasi atau karakter carriage return (Windows) dari input
    SWAP_SIZE_GB=$(echo "$SWAP_SIZE_GB" | tr -d '\r' | tr -d ' ')

    if [[ "$SWAP_SIZE_GB" =~ ^[0-9]+$ && "$SWAP_SIZE_GB" -gt 0 ]]; then
        if [ "$SWAP_SIZE_GB" -ge "$FREE_DISK_GB" ]; then
            echo -e "${RED}✘ Kapasitas disk tidak cukup! Masukkan angka lebih kecil dari ${FREE_DISK_GB}.${NC}"
        else
            break
        fi
    else
        echo -e "${RED}✘ Input tidak valid! Masukkan angka bulat positif.${NC}"
    fi
done

if swapon --show | grep -q "$SWAP_FILE"; then
    print_info "Menghapus swap lama secara aman..."
    sync; echo 3> /proc/sys/vm/drop_caches
    swapoff $SWAP_FILE || print_error "Gagal mematikan swap lama."
    rm -f $SWAP_FILE
    sed -i "\|^$SWAP_FILE|d" /etc/fstab
fi

print_info "Membuat Swap Disk sebesar ${SWAP_SIZE_GB}GB..."
dd if=/dev/zero of=$SWAP_FILE bs=1M count=$((SWAP_SIZE_GB * 1024)) status=progress
chmod 600 $SWAP_FILE
mkswap $SWAP_FILE > /dev/null 2>&1
swapon -p 10 $SWAP_FILE
print_success "Disk Swap siap dengan prioritas 10."

if ! grep -q "^$SWAP_FILE" /etc/fstab; then
    echo "$SWAP_FILE none swap sw,pri=10 0 0" >> /etc/fstab
fi

# ==========================================
# TAHAP 2: KOMPRESI MEMORI (ZSWAP/ZRAM)
# ==========================================
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
print_info "Tahap 2: Konfigurasi Kompresi Memori ($MODE)"

if [[ "$MODE" == "ZSWAP" ]]; then
    # Hapus ZRAM jika sebelumnya terinstal agar tidak bentrok
    if dpkg -l | grep -q "zram-tools"; then
        systemctl stop zramswap > /dev/null 2>&1
        apt-get remove --purge zram-tools -y > /dev/null 2>&1
    fi

    # Injeksi Modul lz4 dan z3fold ke Initramfs agar tidak fallback ke lzo
    print_info "Menyiapkan modul kernel (lz4 & z3fold) untuk ZSWAP..."
    if [[ -f /etc/initramfs-tools/modules ]]; then
        grep -q "^lz4$" /etc/initramfs-tools/modules || echo "lz4" >> /etc/initramfs-tools/modules
        grep -q "^lz4_compress$" /etc/initramfs-tools/modules || echo "lz4_compress" >> /etc/initramfs-tools/modules
        grep -q "^z3fold$" /etc/initramfs-tools/modules || echo "z3fold" >> /etc/initramfs-tools/modules
        
        # Build ulang initramfs secara silent
        update-initramfs -u > /dev/null 2>&1
        print_success "Modul kompresi tingkat lanjut berhasil ditambahkan."
    fi

    # Modifikasi GRUB secara presisi (Aman dijalankan berulang kali)
    sed -i -E 's/zswap\.([a-zA-Z_]+=[^ ]+ *)//g' /etc/default/grub
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="zswap.enabled=1 zswap.compressor=lz4 zswap.max_pool_percent=20 zswap.zpool=z3fold /' /etc/default/grub
    
    update-grub > /dev/null 2>&1
    print_success "ZSWAP (lz4 + z3fold) berhasil dikonfigurasi di GRUB."
    print_info "CATATAN: ZSWAP baru akan berjalan setelah VPS di-reboot."
    
else
    # MODE FALLBACK ZRAM (Untuk LXC/OpenVZ)
    apt-get update -y > /dev/null 2>&1
    apt-get install zram-tools -y > /dev/null 2>&1

    cat <<EOF> /etc/default/zramswap
ALGO=lz4
PERCENT=50
PRIORITY=100
EOF
    systemctl restart zramswap
    print_success "ZRAM berhasil diaktifkan dengan prioritas 100."
fi

echo -e "${PURPLE}\n[ ✓ Instalasi Selesai ]\n${NC}"
echo -e "${YELLOW}Kondisi virtual memory Anda saat ini:${NC}"
swapon --show
if [[ "$MODE" == "ZSWAP" ]]; then
    echo -e "${RED}\n>>> SILAKAN REBOOT VPS ANDA UNTUK MENGAKTIFKAN ZSWAP <<<\n${NC}"
fi