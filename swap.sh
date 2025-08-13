#!/bin/bash

# Script untuk membuat dan mengatur swap pada VPS dengan tampilan estetik
# Pastikan dijalankan sebagai root

# Warna ANSI
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export LIGHT='\033[0;37m'
export NC='\033[0m'

# Fungsi untuk mendapatkan informasi OS
get_os_info() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME="$PRETTY_NAME"
    elif command -v lsb_release >/dev/null 2>&1; then
        OS_NAME=$(lsb_release -ds)
    else
        OS_NAME=$(cat /etc/*release | grep -m1 PRETTY_NAME | cut -d'"' -f2)
    fi
    [ -z "$OS_NAME" ] && OS_NAME="Unknown"
    echo "$OS_NAME"
}

# Fungsi untuk menampilkan informasi sistem
display_info() {
    opsy=$(get_os_info)
    arch=$(uname -m)
    lbit=$(getconf LONG_BIT)
    kern=$(uname -r)

    clear
    echo -e "${YELLOW}┌────────────${NC} ${LIGHT}◈ Informasi Sistem ◈ ${NC}${YELLOW}────────────┐${NC}"
    echo -e "${YELLOW} ➽ OS      : $opsy ${NC}"
    echo -e "${YELLOW} ➽ Arsitektur : $arch ($lbit Bit) ${NC}"
    echo -e "${YELLOW} ➽ Kernel  : $kern ${NC}"
    echo -e "${YELLOW}└─────────────────────────────────────────────────┘${NC}"
    echo " ➽ Skrip untuk mengatur swap secara aman pada VPS"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Fungsi untuk menampilkan pesan sukses biasa (tanpa ASCII art)
print_success() {
    echo -e "${GREEN}✔ $1${NC}"
}

# Fungsi untuk menampilkan pesan sukses akhir dengan ASCII art
print_final_success() {
    echo -e "${PURPLE}\n[ Instalasi selesai dengan sukses ]\n${NC}"
    echo "ulimit -SHn 1000000" >> /etc/profile
    echo -e "${GREEN}✔ $1${NC}"
}

# Fungsi untuk menampilkan pesan error
print_error() {
    echo -e "${RED}✘    ✘ $1${NC}"
}

# Fungsi untuk menampilkan info
print_info() {
    echo -e "${BLUE}➽ $1${NC}"
}

# Periksa apakah script dijalankan sebagai root
if [[ $EUID -ne 0 ]]; then
    display_info
    print_error "Script harus dijalankan sebagai root!"
    exit 1
fi

# Variabel
SWAP_FILE="/swapfile"

# Fungsi untuk menampilkan ruang disk
show_disk_space() {
    print_info "Memeriksa ruang disk yang tersedia..."
    TOTAL_SPACE=$(df -h / | awk 'NR==2 {print $2}')
    AVAILABLE_SPACE=$(df -h / | awk 'NR==2 {print $4}')
    AVAILABLE_KB=$(df / | tail -1 | awk '{print $4}') # Dalam KB
    echo -e "${YELLOW}  Total: ${TOTAL_SPACE} | Tersedia: ${AVAILABLE_SPACE}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Fungsi untuk meminta input ukuran swap
get_swap_size() {
    print_info "Masukkan ukuran swap yang diinginkan"
    while true; do
        echo -e -n "${YELLOW}Ukuran swap (dalam GB, misalnya 2 untuk 2GB): ${NC}"
        read SWAP_SIZE_GB
        # Validasi input adalah angka positif
        if [[ $SWAP_SIZE_GB =~ ^[0-9]+$ && $SWAP_SIZE_GB -gt 0 ]]; then
            SWAP_SIZE="${SWAP_SIZE_GB}G"
            REQUIRED_SPACE=$(( SWAP_SIZE_GB * 1024 * 1024 )) # Konversi ke KB
            if [[ $AVAILABLE_KB -lt $REQUIRED_SPACE ]]; then
                print_error "Ruang disk tidak cukup! Diperlukan minimal ${SWAP_SIZE} ruang kosong."
                print_info "Ruang tersedia: $((AVAILABLE_KB / 1024)) MB"
                exit 1
            fi
            print_success "Ukuran swap diatur ke ${SWAP_SIZE}"
            break
        else
            print_error "Input tidak valid! Masukkan angka positif (contoh: 2 untuk 2GB)."
        fi
    done
}

# Fungsi untuk memeriksa apakah swap sudah ada
check_swap() {
    print_info "Memeriksa keberadaan swap..."
    if [[ -f "$SWAP_FILE" ]]; then
        print_error "File swap sudah ada di $SWAP_FILE!"
        exit 1
    fi
    if swapon --show | grep -q "$SWAP_FILE"; then
        print_error "Swap sudah aktif di $SWAP_FILE!"
        exit 1
    fi
    print_success "Tidak ada swap yang sudah ada"
}

# Fungsi untuk membuat swap
create_swap() {
    print_info "Membuat file swap sebesar $SWAP_SIZE..."
    fallocate -l $SWAP_SIZE $SWAP_FILE
    if [[ $? -ne 0 ]]; then
        print_error "Gagal membuat file swap!"
        exit 1
    fi

    # Atur izin aman
    chmod 600 $SWAP_FILE
    chown root:root $SWAP_FILE
    print_success "Izin file swap diatur"

    # Format sebagai swap
    mkswap $SWAP_FILE
    if [[ $? -ne 0 ]]; then
        print_error "Gagal memformat file swap!"
        rm -f $SWAP_FILE
        exit 1
    fi
    print_success "File swap berhasil diformat"

    # Aktifkan swap
    swapon $SWAP_FILE
    if [[ $? -ne 0 ]]; then
        print_error "Gagal mengaktifkan swap!"
        rm -f $SWAP_FILE
        exit 1
    fi
    print_success "Swap berhasil diaktifkan"
}

# Fungsi untuk mengatur swap di fstab
configure_fstab() {
    print_info "Mengatur swap di /etc/fstab..."
    if ! grep -q "$SWAP_FILE" /etc/fstab; then
        echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
        if [[ $? -ne 0 ]]; then
            print_error "Gagal menambahkan swap ke /etc/fstab!"
            swapoff $SWAP_FILE
            rm -f $SWAP_FILE
            exit 1
        fi
    fi
    print_success "Swap ditambahkan ke /etc/fstab"
}

# Fungsi untuk mengatur parameter swap
configure_sysctl() {
    print_info "Mengatur parameter swap di /etc/sysctl.conf..."
    SYSCTL_FILE="/etc/sysctl.conf"
    SWAPPINESS=10
    CACHE_PRESSURE=50

    # Backup sysctl.conf
    cp $SYSCTL_FILE ${SYSCTL_FILE}.bak
    print_success "Backup sysctl.conf dibuat"

    # Atur swappiness
    if ! grep -q "vm.swappiness" $SYSCTL_FILE; then
        echo "vm.swappiness=$SWAPPINESS" >> $SYSCTL_FILE
    else
        sed -i "s/vm.swappiness=.*/vm.swappiness=$SWAPPINESS/" $SYSCTL_FILE
    fi

    # Atur cache pressure
    if ! grep -q "vm.vfs_cache_pressure" $SYSCTL_FILE; then
        echo "vm.vfs_cache_pressure=$CACHE_PRESSURE" >> $SYSCTL_FILE
    else
        sed -i "s/vm.vfs_cache_pressure=.*/vm.vfs_cache_pressure=$CACHE_PRESSURE/" $SYSCTL_FILE
    fi

    # Terapkan perubahan
    sysctl -p >/dev/null
    print_success "Parameter swap diatur (swappiness=$SWAPPINESS, cache_pressure=$CACHE_PRESSURE)"
}

# Main execution
display_info
print_info "Memulai konfigurasi swap..."

# Tampilkan ruang disk
show_disk_space

# Minta input ukuran swap
get_swap_size

# Lanjutkan proses konfigurasi
check_swap
create_swap
configure_fstab
configure_sysctl

# Verifikasi swap aktif
print_info "Status swap saat ini:"
swapon --show | awk '{print "  ➽ " $1 " (" $3 ")"}'
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
print_final_success "Swap berhasil diatur dengan ukuran $SWAP_SIZE di $SWAP_FILE!"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

exit 0
