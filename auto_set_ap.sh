#!/bin/bash

# Function to check if the script is run as root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "This script must be run as root" 1>&2
        exit 1
    fi
}

# Function to backup a file
backup_file() {
    if [ -f "$1" ]; then
        cp "$1" "$1.bak"
        echo "Backed up $1 to $1.bak"
    fi
}

# 1. Configure /etc/network/interfaces
configure_interfaces() {
    backup_file /etc/network/interfaces
    cat > /etc/network/interfaces << EOF
auto lo
iface lo inet loopback
auto eth0
iface eth0 inet static
    address 192.168.1.50
    netmask 255.255.255.0
    gateway 192.168.1.1
    dns-nameservers 8.8.8.8 8.8.4.4
auto wlan0
iface wlan0 inet static
    address 20.1.1.50
    netmask 255.255.255.0
    wireless-mode master
    wireless-power off
EOF
    echo "Configured /etc/network/interfaces"
}

# 2. Install hostapd and dnsmasq
install_packages() {
    apt update
    apt install -y hostapd dnsmasq
    echo "Installed hostapd and dnsmasq"
}

# 3. Configure /etc/dhcpcd.conf
configure_dhcpcd() {
    backup_file /etc/dhcpcd.conf
    echo "interface wlan0" >> /etc/dhcpcd.conf
    echo "static ip_address=20.1.1.50/24" >> /etc/dhcpcd.conf
    echo "Configured /etc/dhcpcd.conf"
}

# 4. Configure /etc/dnsmasq.conf
configure_dnsmasq() {
    backup_file /etc/dnsmasq.conf
    cat > /etc/dnsmasq.conf << EOF
interface=wlan0
dhcp-range=20.1.1.100,20.1.1.110,255.255.255.0,24h
EOF
    echo "Configured /etc/dnsmasq.conf"
}

# 5. Configure /etc/hostapd/hostapd.conf
configure_hostapd() {
    backup_file /etc/hostapd/hostapd.conf
    cat > /etc/hostapd/hostapd.conf << EOF
interface=wlan0
driver=nl80211
ssid=QNatural
hw_mode=g
channel=7
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=dls@1234
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
ieee80211n=1
wmm_enabled=1
ht_capab=[HT40][SHORT-GI-20][DSSS_CCK-40]
country_code=TH
EOF
    echo "Configured /etc/hostapd/hostapd.conf"
}

# 6. Configure /etc/sysctl.conf
configure_sysctl() {
    backup_file /etc/sysctl.conf
    sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    echo "Configured /etc/sysctl.conf"
}

# 7. Set NAT for eth0
set_nat() {
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT
    echo "Set NAT for eth0"
}

# 8. Save the iptables
save_iptables() {
    sh -c "iptables-save > /etc/iptables.ipv4.nat"
    echo "Saved iptables"
}

# 9. Configure /etc/default/hostapd
configure_default_hostapd() {
    backup_file /etc/default/hostapd
    sed -i 's/#DAEMON_CONF=""/DAEMON_CONF="\/etc\/hostapd\/hostapd.conf"/' /etc/default/hostapd
    echo "Configured /etc/default/hostapd"
}

# 10. Disable NetworkManager and wpa_supplicant
disable_network_services() {
    systemctl stop NetworkManager
    systemctl disable NetworkManager
    systemctl stop wpa_supplicant
    systemctl disable wpa_supplicant
    echo "Disabled NetworkManager and wpa_supplicant"
}

# 11. Create watchdog script
create_watchdog_script() {
    cat > /usr/local/bin/ap_watchdog.sh << EOF
#!/bin/bash
while true; do
  if ! iw dev wlan0 info | grep -q "type AP"; then
    systemctl restart hostapd
  fi
  sleep 60
done
EOF
    chmod +x /usr/local/bin/ap_watchdog.sh
    echo "Created watchdog script"
}

# 12. Create systemd service for watchdog
create_watchdog_service() {
    cat > /etc/systemd/system/ap-watchdog.service << EOF
[Unit]
Description=AP Watchdog Service
After=network.target
[Service]
ExecStart=/usr/local/bin/ap_watchdog.sh
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    systemctl enable ap-watchdog.service
    echo "Created and enabled watchdog service"
}

# 13. Edit dnsmasq service to delay start
edit_dnsmasq_service() {
    backup_file /lib/systemd/system/dnsmasq.service
    sed -i '/\[Unit\]/a After=network.target' /lib/systemd/system/dnsmasq.service
    sed -i '/\[Service\]/a ExecStartPre=/bin/sleep 15' /lib/systemd/system/dnsmasq.service
    echo "Edited dnsmasq service"

    # Enable dnsmasq service to start on boot
    systemctl enable dnsmasq.service
    echo "Enabled dnsmasq service to start on boot"
}

# 14. Remove bind-interfaces in dnsmasq and other files
remove_bind_interfaces() {
    sed -i 's/bind-interfaces/#bind-interfaces/' /etc/dnsmasq.conf
    grep -r "bind-interface" /etc/dnsmasq.d/ | xargs sed -i 's/bind-interface/#bind-interface/'
    grep -r "bind-interfaces" /etc/ | xargs sed -i 's/bind-interfaces/#bind-interfaces/'
    echo "Removed bind-interfaces"
}

# Main function
main() {
    check_root
    configure_interfaces
    install_packages
    configure_dhcpcd
    configure_dnsmasq
    configure_hostapd
    configure_sysctl
    set_nat
    save_iptables
    configure_default_hostapd
    disable_network_services
    create_watchdog_script
    create_watchdog_service
    edit_dnsmasq_service
    remove_bind_interfaces
    echo "All configurations complete. Rebooting in 5 seconds..."
    sleep 5
    reboot
}

# Run the main function
main
