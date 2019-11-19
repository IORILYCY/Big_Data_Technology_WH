# CentOS7离线安装CDH5.15

---
## 一、准备工作
<font color=#DC143C>！！！注意：以下操作除MySQL的安装外所有点都需要执行，且需要root权限</font>
### （一）关闭防火墙、SELINUX、IPv6
#### 1. 修改主机名及hosts
##### 1.1. 修改主机名
```shell
sudo hostnamectl set-hostname cdh001
```
##### 1.2. 修改hosts
```shell
sudo vim /etc/hosts
```
```shell
# 增加：
30.23.77.57 cdh001
30.23.77.58 cdh002
30.23.77.59 cdh003
```
#### 2. 关闭防火墙
##### 2.1. 临时关闭
```shell
sudo systemctl stop firewalld.service
```
##### 2.2. 关闭开机自启
```shell
sudo systemctl disable firewalld.service
```
#### 3. 关闭SELINUX
##### 3.1. 编辑配置文件
```shell
sudo vim /etc/selinux/config
```
```shell
# 修改：
SELINUX=disable
```
#### 4. 关闭IPv6
##### 4.1. 编辑配置文件
```shell
sudo vim /etc/sysvtl.conf
```
```shell
# 增加：
net.ipv6.conf.all.disable_ipv6=1
```
```shell
sudo vim /etc/sysconfig/network
```
```shell
# 增加：
NETWORKING_IPV6=no
```
##### 4.2. 编辑网卡配置
```shell
sudo vim /etc/sysconfig/network-scripts/ifcfg-eth0
```
```shell
# 修改或增加：
IPV6INIT=no
```
##### 4.3 执行以下命令生效
```shell
sudo sysctl -p
```

---
### （二）配置集群时间同步
#### 1. 所有节点安装ntp服务
```shell
sudo yum -y install ntp
```
#### 2. 配置Server
##### 2.1. 修改ntp配置文件
```shell
sudo vim /etc/ntp.conf
```
```shell
# 修改：
# Hosts on local network are less restricted.
restrict 30.23.77.0 mask 255.255.255.0 nomodify notrap

# 注释：
#server 0.contos.pool.ntp.org iburst
#server 1.contos.pool.ntp.org iburst
#server 2.contos.pool.ntp.org iburst
#server 3.contos.pool.ntp.org iburst

# 增加：
server 127.127.1.0
fudge 127.127.1.0 stratum 10
```
##### 2.2. 修改ntpd配置文件
```shell
sudo vim /etc/sysconfig/ntpd
```
```shell
# 增加：
SYNC_HWCLOCK=yes
```
#### 3. 配置其他节点
##### 3.1. 修改ntp配置文件
```shell
sudo vim /etc/ntp.conf
```
```shell
# 注释：
#server 0.contos.pool.ntp.org iburst
#server 1.contos.pool.ntp.org iburst
#server 2.contos.pool.ntp.org iburst
#server 3.contos.pool.ntp.org iburst

# 增加：
server 30.23.77.57
```
#### 4. 开启ntp服务
```shell
# 启动服务
sudo systemctl start ntpd
```
```shell
# 配置开机自启
sudo systemctl enable ntpd
```

---
### （三）配置集群间ssh免密登录
<font color=#DC143C>！！！注意：为防止出错，所有节点之间都要配置</font>
#### 1. 生成秘钥
```shell
ssh-keygen -t rsa
# 根据提示连续三次回车
```
#### 2. 发送秘钥到目标节点
```shell
ssh-copy-id 主机名
```
#### 3. 登录目标节点
```shell
ssh 主机名
# 第一次连接需要输入密码
```
#### 4. 切换到root用户重复以上操作

---
### （四）安装Java
#### 1. 卸载原生的Open JDK
##### 1.1. 查询已安装的JDK
```shell
sudo rpm -qa | grep -i jdk
```
##### 1.2. 卸载JDK
```shell
sudo yum remove -y copy-jdk-config…
```
#### 2. 安装Oracle JDK
##### 2.1. 上传下载的tar包并解压
```shell
tar -zxvf jdk-8u181-linux-x64.tar.gz -C /usr/openv
```
