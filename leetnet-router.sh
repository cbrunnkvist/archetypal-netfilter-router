#!/bin/bash

# --- Configuration ---
UPSTREAM_IF="builtin-fe0"
UPSTREAM_STATIC_IP="192.168.1.42" # Static IP of the upstream interface
LAN_IF="lan-bridge"
LAN_NET="10.13.37.0/24"     # Your private LAN
ENABLE_WAN_DHCP_LOGGING=true # Set to false to disable logging of WAN DHCP attempts

# --- 1. Flush existing rules and delete user-defined chains ---
echo "Flushing existing rules and LEETNET chains..."
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F

# Delete user-defined chains if they exist (ignore errors if they don't)
sudo iptables -X LEETNET_INPUT 2>/dev/null
sudo iptables -X LEETNET_FORWARD 2>/dev/null
sudo iptables -X LOG_WAN_DHCP_ATTEMPTS 2>/dev/null
sudo iptables -X

# Zero counters
sudo iptables -Z
sudo iptables -t nat -Z
sudo iptables -t mangle -Z

# --- 2. Set default policies ---
echo "Setting default policies..."
sudo iptables -P INPUT DROP
sudo iptables -P FORWARD DROP
sudo iptables -P OUTPUT ACCEPT

# --- 3. Create LEETNET and Logging user-defined chains ---
echo "Creating user-defined chains..."
sudo iptables -N LEETNET_INPUT
sudo iptables -N LEETNET_FORWARD
sudo iptables -N LOG_WAN_DHCP_ATTEMPTS

# --- 4. Populate dedicated logging chain (conditionally) ---
if [ "$ENABLE_WAN_DHCP_LOGGING" = true ]; then
  sudo iptables -A LOG_WAN_DHCP_ATTEMPTS -j LOG --log-prefix "LEETNET_WAN_DHCP_DROP: " --log-level 7
fi
sudo iptables -A LOG_WAN_DHCP_ATTEMPTS -j RETURN

# --- 5. Populate LEETNET_INPUT chain (for traffic TO the gateway) ---
sudo iptables -A LEETNET_INPUT -i "${UPSTREAM_IF}" -p udp --dport 67 -j LOG_WAN_DHCP_ATTEMPTS
sudo iptables -A LEETNET_INPUT -i "${UPSTREAM_IF}" -p udp --dport 67 -j DROP

sudo iptables -A LEETNET_INPUT -i "${LAN_IF}" -p udp --dport 67 -j ACCEPT

sudo iptables -A LEETNET_INPUT -i "${LAN_IF}" -s "${LAN_NET}" -j ACCEPT

# --- 6. Populate LEETNET_FORWARD chain (for traffic THROUGH the gateway) ---
sudo iptables -A LEETNET_FORWARD -i "${LAN_IF}" -o "${UPSTREAM_IF}" -s "${LAN_NET}" -j ACCEPT

# --- 7. Populate main INPUT chain ---
echo "Populating main INPUT chain..."
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT -i "${LAN_IF}" -j LEETNET_INPUT
sudo iptables -A INPUT -i "${UPSTREAM_IF}" -j LEETNET_INPUT

# --- 8. Populate main FORWARD chain ---
echo "Populating main FORWARD chain..."
sudo iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -j LEETNET_FORWARD

# --- 9. NAT (SNAT) in the nat table ---
echo "Applying NAT (SNAT)..."
sudo iptables -t nat -A POSTROUTING -o "${UPSTREAM_IF}" -s "${LAN_NET}" -j SNAT --to-source "${UPSTREAM_STATIC_IP}"

echo "IPTables rules applied with LEETNET chains, LAN_IF=${LAN_IF}, using SNAT to ${UPSTREAM_STATIC_IP}."
echo "Verify with:"
echo "  sudo iptables -L -v -n"
echo "  sudo iptables -L LEETNET_INPUT -v -n"
echo "  sudo iptables -L LEETNET_FORWARD -v -n"
echo "  sudo iptables -L LOG_WAN_DHCP_ATTEMPTS -v -n"
echo "  sudo iptables -t nat -L -v -n"
