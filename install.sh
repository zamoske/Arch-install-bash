#!bin/bash

#цвета для различных логов
COLOR_GOOD='\033[0;32m'
COLOR_BAD='\033[0;31m'
COLOR_INFO='\033[0;34m'
COLOR_NC='\033[0m'
COLOR_WARN='\033[;33m'

required_var () {
    echo -e "${COLOR_BAD}Все необходимые переменные не заданы${COLOR_NC}"
    echo  "Необходимые переменные:"
    echo "1) Путь до желаемого диска для установки:DISK"
    echo "2) Пароль root:PASSWORD"
    echo "3) Имя пользователь:USRNAME"
    echo "4) Пароль пользователя:USR_PASSWORD"
    echo "5) Желаемый IP:ADDRESS"
    echo "6) Желаемый шлюз:GATEWAY"
    exit 1
}

command () {
    $1 1>/dev/null 2>/dev/null
    return $?
}

log_good () { 
    echo -e "${COLOR_GOOD}${1}${COLOR_NC}"
}

log_warn () {
    echo -e "${COLOR_WARN}${1}${COLOR_NC}"
}

log_bad () {
    echo -e "${COLOR_BAD}${1}${COLOR_NC}"
    exit 1
}

log_info () {
    echo -e "${COLOR_INFO}${1}${COLOR_NC}"
}

#настраеваемые параметры
SYS_PKG="base linux linux-headers f2fs-tools which netctl inetutils base-devel efibootmgr wget linux-firmware grub vim pam git go"
USR_PKG="plasma plasma-meta plasma-pa plasma-desktop kde-system-meta kde-utilities-meta konsole kio-extras latte-dock sddm sddm-kcm"
ZONE_INFO=/usr/share/zoneinfo/Europe/Moscow
WARN_COUNT=0
NETWORK_INTERFACE="eth0"

export LANG=ru_RU.UTF-8

test -z $DISK && log_warn "Путь до диска для установки не задан:'$DISK'" && ((WARN_COUNT+=1))
test -z $PASSWORD && log_warn "Пароль root не задан:'$PASSWORD'" && ((WARN_COUNT+=1))
test -z $USRNAME && log_warn "Имя пользователя не задано:'$USRNAME'" && ((WARN_COUNT+=1))
test -z $USR_PASSWORD && log_warn "Пароль для пользователя не задан:'$USR_PASSWWORD'" && ((WARN_COUNT+=1))
test -z $ADDRESS && log_warn "Желаемый IP не задан:'$ADDRESS'" && ((WARN_COUNT+=1))
test -z $GATEWAY && log_warn "Желаемый шлюз не задан:'$GATEWAY'" && ((WARN_COUNT+=1))
test $WARN_COUNT -gt 0 && required_var 

log_info "Размонтирование и удаление старых разделов"
for partition in $(parted -s $DISK print | awk '/^ / {print $1}')
    do
        umount -f $DISK${partition}
        parted -s $DISK rm ${partition}
        test $? != 0 && log_bad "Ошибка размонтирования и удаления старых разделов"
    done
    log_good "Старые разедлы размонтированы и удалены"


log_info "Разбивка диска"
parted -s -a optimal $DISK \
    mklabel gpt \
    mkpart "EFI" fat32 1MiB 261MiB \
    set 1 boot on \
    mkpart "home" ext4 261MiB 50%\
    mkpart "root" ext4 50% 100% \
    quit
    
test $? != 0 && log_bad "Ошибка при разбивке диска"
log_good "Разделы созданы"

log_info "Форматирование дисков"
yes | mkfs.fat -F32 $DISK'1'
yes | mkfs.ext4 $DISK'2'
yes | mkfs.ext4 $DISK'3'
log_info "Форматирование успешно проведено"
 
log_info "Сейчас будет проводиться монтирование разделов"
mount $DISK'3' /mnt
test $? != 0 && log_bad "Ошибка монтирования раздела root"
log_good "Раздел root успешно смонтирован"
mount --mkdir $DISK'2' /mnt/home
test $? != 0 && log_bad "Ошибка монитрования раздела home"
log_good "Раздел home успешно смонтирован"
mount --mkdir $DISK'1' /mnt/boot
test $? != 0 && log_bad "Ошибка монитрования загрузочного раздела"
log_good "Загрузочный раздел успешно смонтирован"

pacman-key --populate archlinux
pacman -S archlinux-keyring --noconfirm

log_info "Сейчас будет производиться установка основных пакетов"
command "pacstrap /mnt $SYS_PKG --noconfirm"
test $? != 0 && log_bad "Ошибка установки"
log_good "Установка основных пакетов завершена успешно"

arch-chroot /mnt mkinitcpio -p linux

log_info "Генерация файла fstab"
genfstab -U /mnt >> /mnt/etc/fstab
test $? != 0 && log_bad "Ошибка генерации файла fstab"
log_good "Файл fstab успешно сгенерирован"

log_info "Сейчас будет производиться настройка локализации и времени, а также добавление пользователя и выдача прав"
cat << EOF | arch-chroot /mnt
echo "Добавление русской раскладки и локолизации"
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo 'LANG="ru_RU.UTF-8"' > /etc/locale.conf 
echo "KEYMAP=ru" >> /etc/vconsole.conf
echo "FONT=cyr-sun16" >> /etc/vconsole.conf
echo "Установление тайм-зоны"
ln -svf $ZONE_INFO /etc/localtime
hwclock --systohc --utc
grub-install grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
echo "Добавление пользователей"
useradd -m -g users -G wheel -s /bin/bash $USRNAME
echo "пароль для '$USRNAME' был случайно сгенерирован:'$USR_PASSWORD'"
echo "$USRNAME:$USR_PASSWORD" | chpasswd
echo "root:$PASSWORD" | chpasswd
echo '%wheel ALL=(ALL) ALL' >> /etc/sudoers
echo '%wheel ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
EOF

log_info "Настройка сети"
MACADDRESS="$(ip a | grep ether | gawk '{print $2}')"
arch-chroot /mnt mkdir -p /etc/udev/rules.d
arch-chroot /mnt systemctl enable systemd-networkd

cat << EOF > /mnt/etc/udev/rules.d/10-network.rules
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="$MACADDRESS, NAME="$NETWORK_INTERFACE"
EOF

cat << EOF > /mnt/etc/systemd/network/$NETWORK_INTERFACE.network
[Match]
Name=$NETWORK_INTERFACE

[Network]
Address=$ADDRESS/24
Gateway=$GATEWAY
DNS=8.8.8.8
EOF

cat << EOF > /mnt/etc/systemd/resolve.conf
[Resolve]
DNS=8.8.8.8
Domains=~.
EOF

log_info "Сейчас будет проводиться установка Aur-helper'а yay"
cat << EOF | arch-chroot /mnt
su - $USRNAME
cd /home/$USRNAME
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
EOF

log_info "Сейчас будет проводиться установка окружения plasma"
command "pacstrap /mnt $USR_PKG --noconfirm" 
test $? != 0 && log_bad "Ошибка установки"
log_good "Установка завершена"
log_info "Добавление мененджера входа в автозагрузку"
arch-chroot /mnt systemctl enable sddm.service -f
test $? != 0 && log_bad "Ошибка добавления в автозагрузку"
log_good "Успешно добавлен в автозагрузку"

cat << EOF | arch-chroot /mnt
su - $USRNAME
mkdir -p /home/$USRNAME/.config
EOF

log_info "Добавления горячей клавиши для октрытия konsole через Win + Enter"
cat << EOF >> /mnt/home/$USRNAME/.config/kglobalshortcutsrc
[org.kde.konsole.desktop]
NewTab=none,none,Открыть новую вкладку
NewWindow=Meta+Return,none,Открыть новое окно
_k_friendly_name=Konsole
_launch=Ctrl+Alt+T,Ctrl+Alt+T,Konsole
EOF

log_good "Поздравляю, установка завершена, далее последует перезагрузка"
reboot
