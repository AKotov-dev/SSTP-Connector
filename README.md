# SSTP-Connector
Simple SSTP (Secure Socket Tunneling Protocol) VPN connector  
  
**Dependencies:** sstp-client gtk2 polkit fping procps-ng resolvconf systemd
  
Secure Socket Tunneling Protocol (SSTP) transports a PPP tunnel over a TLS channel. The use of TLS over TCP port 443 allows SSTP to pass through virtually all firewalls and proxy servers. If a different port is used, `don't forget to open it in iptables`.
  
![](https://github.com/AKotov-dev/SSTP-Connector/blob/main/ScreenShot3.png)
