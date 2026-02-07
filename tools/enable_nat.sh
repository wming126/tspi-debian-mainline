sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -o wlp4s0 -j MASQUERADE
sudo ifconfig enx6a554225418f 192.168.7.1
sudo iptables -A FORWARD -i enx6a554225418f -j ACCEPT
