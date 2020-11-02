OpenVPN
===
## 简介
* **OpenVPN** 是一个基于 OpenSSL 库的应用层 VPN 实现。和传统 VPN 相比，它的优点是简单易用。
> * 官方站点：https://openvpn.net/index.php/open-source.html


## Example:

    #运行一个openvpn
    docker run -d --restart unless-stopped --cap-add NET_ADMIN --device /dev/net/tun -v /docker/openvpn:/key -p 1194:1194 --name openvpn jiobxn/openvpn

    #运行一个client
    docker run -d --restart unless-stopped --cap-add NET_ADMIN --device /dev/net/tun -v /docker/ovpn:/key --name ovpn jiobxn/openvpn:client

    #运行一个http代理的openvpn
    docker run -d --restart unless-stopped --cap-add NET_ADMIN --device /dev/net/tun -v /docker/openvpn:/key -p 8080:8080 -e PROXY_USER=jiobxn --name openvpn jiobxn/openvpn
    # client需要把http认证auth.txt 放到/docker/ovpn/auth.txt

    #运行一个redius用户认证的openvpn
    docker run -d --restart unless-stopped --cap-add NET_ADMIN --device /dev/net/tun -v /docker/openvpn:/key -p 8080:8080 -e RADIUS_SERVER=<redius-ip> -e VPN_USER=Y --name openvpn jiobxn/openvpn
    # 用户名密码可以写在一个文件，例如 echo -e "root\npassword" >/docker/ovpn/pwd.txt 。然后修改client.ovpn 配置文件91行 auth-user-pass pwd.txt  


## Run Defult Parameter
**协定：** []是默参数，<>是自定义参数

			docker run -d --restart unless-stopped --cap-add NET_ADMIN --device /dev/net/tun \\
			-v /docker/openvpn:/key \\
			-p 1194:1194 \\
			-p <8080:8080> \\
			-e TCP_UDP=[tcp] \\    默认使用TCP
			-e TAP_TUN=[tun] \\    默认使用tun(IP/三层)；tap是以太网/二层（tap和MAX_STATICIP同时使用 Windows client会无法连接）
			-e VPN_PORT=[1194] \\  默认端口
			-e VPN_USER=<jiobxn> \\  VPN用户名
			-e VPN_PASS=<RANDOM> \\  VPN密码，默认随机，/docker/openvpn/openvpn.log
			-e MAX_STATICIP=<1000> \\  最大固定IP客户端数，/docker/openvpn/client.txt
			-e C_TO_C=[Y] \\         允许客户端与客户端之间通信
			-e GATEWAY_VPN=[Y] \\    默认VPN做网关
			-e PUSH_ROUTE=<"192.168.0.0/255.255.0.0,172.16.0.0/255.240.0.0,10.0.0.0/255.0.0.0">    推送路由，适用于GATEWAY_VPN=N
			-e SERVER_IP=[SERVER_IP] \\  默认是服务器公网IP
			-e IP_RANGE=[10.8] \\        分配的IP地址池
			-e PROXY_USER=<jiobxn> \\    http代理用户名
			-e PROXY_PASS=<RANDOM> \\    代理密码，默认随机
			-e PROXY_PORT=[8080] \\      代理端口
			-e DNS1=[9.9.9.9] \\         默认DNS
			-e DNS2=[8.8.8.8] \\
			-e RADIUS_SERVER=<radius ip> \\    radius 服务器
			-e RADIUS_SECRET=[testing123] \\   radius 共享密钥
			-e NAT_RANGE=<10.10.100 | 10.10.100.100> \\         NAT的IP地址池，将10.8.0.x DNAT> 10.10.100.x
			--name openvpn openvpn

### IOS Client:

    1.到App Store 安装OpenVPN.
    2.用iTunes 导入ta.key、auth.txt和client.ovpn 到OpenVPN

### [Tunnelblick](https://tunnelblick.net/index.html)、[OpenVPN Connect Client](https://openvpn.net/downloads/openvpn-connect-v3-macos.dmg)

### Linux Client:

    1.安装 yum -y install openvpn
    2.传输文件 scp OpenVPN-Server-IP:/etc/openvpn/{client.conf,auth.txt} /etc/openvpn/
    3.启动 systemctl start openvpn@client.service
    前台启动：openvpn --writepid /var/run/openvpn-client/client.pid --cd /etc/openvpn/ --config /etc/openvpn/client.conf

### Windows Client:

    1.下载并安装 https://openvpn.net/community-downloads/
    2.将client.ovpn和auth.txt(如果有)拷贝到"C:\Program Files\OpenVPN\config\"

### 用户名+密码+证书 自动连接

    cd C:\Program Files\OpenVPN\bin
    openvpn.exe --config ../config/client.ovpn --auth-user-pass ../config/pwd.txt
    # 或修改配置文件91行 auth-user-pass pwd.txt
    # pwd.txt 第一行用户名，第二行密码
