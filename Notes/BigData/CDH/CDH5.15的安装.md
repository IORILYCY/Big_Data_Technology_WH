# CentOS7离线安装CDH5.15

---
## 一、准备工作
<font color=#DC143C>！！！注意：以下操作除MySQL的安装外所有点都需要执行，且需要root权限！！！</font>
### （一）关闭防火墙、SELINUX、IPv6
#### 1. 修改主机名及hosts
##### 1.1. 修改主机名
```shell
sudo hostnamectl set-hostname cdh001
```
##### 1.2. 修改hosts
```shell
sudo vim /etc/hosts
#
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
```shell
sudo vim /etc/selinux/config
#
# 修改：
SELINUX=disable
```
#### 4. 关闭IPv6
##### 4.1. 编辑配置文件
```shell
sudo vim /etc/sysvtl.conf
#
# 增加：
net.ipv6.conf.all.disable_ipv6=1
```
```shell
sudo vim /etc/sysconfig/network
#
# 增加：
NETWORKING_IPV6=no
```
##### 4.2. 编辑网卡配置
```shell
sudo vim /etc/sysconfig/network-scripts/ifcfg-eth0
#
# 修改或增加：
IPV6INIT=no
```
##### 4.3 执行`sudo sysctl -p`命令生效

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
#
# 修改：
# Hosts on local network are less restricted.
restrict 30.23.77.0 mask 255.255.255.0 nomodify notrap
#
# 注释：
#server 0.contos.pool.ntp.org iburst
#server 1.contos.pool.ntp.org iburst
#server 2.contos.pool.ntp.org iburst
#server 3.contos.pool.ntp.org iburst
#
# 增加：
server 127.127.1.0
fudge 127.127.1.0 stratum 10
```
##### 2.2. 修改ntpd配置文件
```shell
sudo vim /etc/sysconfig/ntpd
#
# 增加：
SYNC_HWCLOCK=yes
```
#### 3. 配置其他节点
##### 3.1. 修改ntp配置文件
```shell
sudo vim /etc/ntp.conf
#
# 注释：
#server 0.contos.pool.ntp.org iburst
#server 1.contos.pool.ntp.org iburst
#server 2.contos.pool.ntp.org iburst
#server 3.contos.pool.ntp.org iburst
#
# 增加：
server 30.23.77.57
```
#### 4. 开启ntp服务
##### 4.1. 启动服务
```shell
sudo systemctl start ntpd
```
##### 4.2. 配置开机自启
```shell
sudo systemctl enable ntpd
```

---
### （三）配置集群间ssh免密登录
<font color=#DC143C>！！！注意：为防止出错，所有节点之间都要配置！！！</font>
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
#### 3. 配置环境变量
##### 3.1. 修改/etc/profile
```shell
sudo vim /etc/profile
#
# 增加：
#JAVA_HOME
export JAVA_HOME=/usr/openv/jdk1.8.0_181
export PATH=$PATH:$JAVA_HOME/bin
```
##### 3.2. 为CM创建软连接
* CDH不会自动使用系统环境变量中的JAVA_HOME，而是使用Bigtop进行管理，如果不是在默认位置安装的jdk，就需要创建软连接工CDH使用。
```shell
sudo ln -s /usr/openv/jdk1.8.0_181 jdk1.8
```

---
### （五）安装MySQL
#### 1. 卸载已安装的MySQL
##### 1.1. 查看已安装的MySQL
```shell
sudo rpm -qa | grep -i mysql
```
##### 1.2. 卸载已安装的MySQL
```shell
sudo rpm -e postfix-2.10.1-6.el7.x86_64
sudo rpm -e mariadb-libs-5.5.56-2.el7.x86_64-nodeps
……
```
#### 2. 安装MySQL
<font color=#DC143C>！！！注意：所有节点都需要安装shared-compat组件！！！</font>
```shell
sudo rpm -ivh MySQL-client-5.6.45-1.el7.x86_64.rpm
sudo rpm -ivh MySQL-shared-compat-5.6.45-1.el7.x86_64.rpm
sudo rpm -ivh MySQL-server-5.6.45-1.el7.x86_64.rpm
```
#### 3. 配置MySQL
##### 3.1. 启动MySQL服务
```shell
# 启动服务
sudo systemctl start mysql.service
# 查看临时密码
sudo cat /root/.mysql_secret
# 登录数据库
mysql -uroot -p临时密码
```
##### 3.2. 修改密码
```shell
set password=password(‘123456’);
```
##### 3.3. 配置远程连接
```shell
# 修改连接方式为%：
use mysql;
update user set host=‘%’ where host=‘localhost’;
# 刷新权限：
flush privileges;
```
##### 3.4. 创建CM的数据库
```shell
create database hive DEFAULT utf8 COLLATE utf8_general_ci;
create database amon DEFAULT utf8 COLLATE utf8_general_ci;
create database hue DEFAULT utf8 COLLATE utf8_general_ci;
create database oozie DEFAULT utf8 COLLATE utf8_general_ci;
create database sentry DEFAULT utf8 COLLATE utf8_general_ci;
```

---
---
## 二、安装Cloudera Manager
* CM下载地址：[下载CM5](https://archive.cloudera.com/cm5/cm/5/)
* Parcel下载地址：[下载CDH5.15](https://archive.cloudera.com/cdh5/parcels/5.15.2.3/)
### 1. 解压安装CM
```shell
# 创建安装路径：
mkdir /usr/openv/cdh-5.15.2
# 解压CM：
tar -zxvf cloudera-manager-centos7-cm5.15.2_x86_64.tar.gz -C \
/usr/openv/cdh-5.15.2
```
### 2. 安装第三方依赖
```shell
sudo yum -y install chkconfig python bind-utils psmisc libxslt zlib sqlite cyrus-sasl-plain cyrus-sasl-gssapi fuse fuse-libs redhat-lsb httpd mod_ssl
```
### 3. 配置MySQL驱动
```shell
# 复制驱动包到/usr/share/java并改名
sudo cp mysql-connector-java-5.1.14-bin.jar /usr/share/java/mysql-connector-java.jar
# 复制驱动包到cm-5.15.2/share/cmf/lib并改名
cp mysql-connector-java-5.1.14-bin.jar /usr/share/java/mysql-connector-java.jar
```
### 4. 修改Agent配置
```shell
vim cm-5.15.2/ect/cloudera-scm-agent/config.ini
#
# 修改：
server_host=cdh001
```
### 5. 分发文件到其他节点
#### 5.1. 分发脚本
```shell
#!/bin/bash
#
#1 获取输入参数个数，如果没有参数，直接退出
pcount=$#
if ((pcount==0))
then
    echo no args;
    exit;
fi
#
#2 获取文件名称
p1=$1
fname=`basename $p1`
echo fname=$fname
#
#3 获取上级目录到绝对路径
pdir=`cd -P $(dirname $p1); pwd`
echo pdir=$pdir
#
#4 获取当前用户名称
user=`whoami`
#
#5 循环分发
for((host=001; host<=003; host++))
do
    echo -------------- cdh$host --------------
    rsync -av $pdir/$fname $user@cdh$host:$pdir
done
```
#### 5.2. 分发文件
```shell
xsync cdh-5.15.2
```
### 6. 所有节点创建CM用户
```shell
sudo useradd --system --home=cm-5.15.2/run/cloudera-scm-server/ --no-create-home --shell=/bin/false --comment “Cloudera SCM User” cloudera-scm
```
### 7. 初始化CM数据库
```shell
sudo cm-5.15.2/share/cmf/schema/scm_prepare_database.sh mysql cm -h cdh001 -uroot -p123456 –-scm-host cdh001 scm scm scm
```
### 8. 准备Parcel文件及安装路径
* 上传CDH的三个文件到cdh-5.15.2/cloudera/parcel-repo路径下
#### 8.1. 所有节点创建parcels文件夹
```shell
mkdir cdh-5.15.2/cloudera/parcels
```
#### 8.2. 修改parcel-repo和parcels的所有者
```shell
sudo chown cloudera-scm:cloudera-scm parcel-repo parcels
```
### 9. 启动CM
#### 9.1. 主节点
```shell
sudo cm-5.15.2/etc/init.d/cloudera-scm-server start
sudo cm-5.15.2/etc/init.d/cloudera-scm-agent start
```
#### 9.2. 其他节点
```shell
sudo cm-5.15.2/etc/init.d/cloudera-scm-agent start
```
#### 9.3. 查看端口
* 7180端口被占用则代表服务启动成功
```shell
sudo netstat -anp | grep 7180
```

---
---
## 三、安装服务
### （一）Web页面安装CDH组件
#### 1. 登录Web页面
* 用户名：admin
* 密码：admin
#### 2. 选择CM版本
#### 3. 选择主机
#### 4. 选择parcel方式安装
#### 5. 将CDH部署到所有节点并激活
#### 6. 主机检查
#### 7. 选择需要安装的组件
#### 8. 配置主机角色
#### 9. 配置数据库
* 所有节点都要安装MySQL的shared-compat组件，否则此处会连接不到数据库
#### 10、使用默认配置至安装结束

---
### （二）Parcel方式安装Spark2
#### 1. 下载地址
* 下载csd：[下载Spark2/csd](http://archive:cloudera.com/spark/csd)
* 下载parcel：[下载Spark2/parcel](http://archive:cloudera.com/spark2/parcels/2.3.0.cloudera4)
* parcel的版本必须与csd相匹配
#### 2. 上传文件
* 将在csd页面下载的jar包上传到……cloudera/csd文件下
* 将剩余的3个文件上传到主机的……cloudera/parcel-repo文件夹下，并将…….sha1文件改名为…….sha，修改所有者为cloudera-scm
#### 3. 集群部署
##### 3.1 配置路径
* CM主页：管理->设置，搜索本地，修改csd、parcel-repo、parcels路径，重启server和agent服务
##### 3.2 激活
* CM主页：主机->parcel，选择Spark2，分配->激活
##### 3.3 添加服务
1. CM主页：添加服务，选择Spark2
2. 选择依赖关系
3. 分配主机，Gateway所有主机都要安装
4. 默认配置至安装结束

---
### （三）Parcel方式安装LZO
* 下载地址：[下载LZO](http://archive.cloudera.com/gplextras5/parcels/5.15.2.3)
#### 1. 上传文件
* 将下载的3个文件上传到主机的……cloudera/parcel-repo文件夹下，并将…….sha1文件改名为…….sha，修改所有者为cloudera-scm
#### 2. 集群部署
##### 2.1 激活
1. CM主页：主机->parcel，检查新parcel
2. 选择GPLEXTRAS，分配->激活
##### 2.2 修改HDFS配置
* 压缩格式添加：
```
com.hadoop.compression.lzo.LzoCodec
com.hadoop.compression.lzo.LzopCodec
```
##### 2.3 修改YARN配置
1. MR程序classpath添加：
```
……/CDH/cloudera/parcels/GPLEXTRAS/lib/hadoop/lib
```
2. MR程序运行环境添加：
```
;……/ CDH/cloudera/parcels/GPLEXTRAS/lib/hadoop/lib/native
```

---
---
## 四、安装过程中的一些问题及解决办法
### （一）Server启动问题
```
ERROR main:org.hibernate.engine.jdbc.spi.SqlExceptionHelper: Table ‘cm.CM_VERSION’ doesn’t exist
#
# 缺少表cm.CM_VERSION，不影响使用，可忽略
```
```
ERROR WebServerImpl:com.cloudera.server.web.cmf.search.components.SearchRepositoryManager: The server storage directory [/var/lib/cloudera-scm-server] doesn’t exist
#
# 手动创建/var/lib/cloudera-scm-server
```
```
ERROR WebServerImpl:com.cloudera.server.web.cmf.search.components.SearchRepositoryManager: No read/write permission to the server storage directory [/var/lib/cloudera-scm-server]
#
# 手动修改[/var/lib/cloudera-scm-server]文件夹所有者
```
```
ERROR ParcelUpdateService:com.cloudera.parcel.components.ParcelDownloaderImpl: Unable to retrieve remote parcel repository manifest
#
# 服务器未联网，无法从cm官网获取manifest，不影响使用，可忽略
```
### （二）Agent启动问题
```
MainThread agent ERROR Failed to connect to previous supervisor.
#
# 1）确保集群NTP同步服务有效后重启agent
# 2）服务器重启后在启动agent有时也会报此错误，此时杀掉supervisor进程，重启agent
```
```
MainThread parcel ERROR Failed to activate alternatives for parcel ……
MainThread parcel ERROR Failed to deactivate alternatives for parcel ……
#
# 1）查看/etc/alternatives/、/usr/bin/路径下是否缺少对应的软连接，并手动创建
# 2）脚本命令连接至：parcels/CDH/bin
# 3）conf路径连接至：parcels/CDH/etc/组件名/conf.
```
```
MonitorDaemom-Reporter throttling_logger ERROR sending messages to firehose: mgmt-HOSTMONITOR-……
#
# 前一项错误未处理agent进程也不会dead，但在Web安装组件时会报此错误，处理完即可解决
```
```
Monitor-GenericMonitor throttling_logger ERROR fetching metrics at ‘http://host:60030/jmx’
#
# 检查主机名、hosts、agent的server配置是否一致
```

---
### （三）HDFS权限报错
CDH默认用户hdfs:supergroup为HDFS的最高管理用户，普通用户启动spark、kylin等对HDFS有写需求的服务时会报对HDFS没有写权限的错，此时可通过将用户添加到supergroup组来解决权限问题
#### 1. 添加supergroup组
```shell
sudo groupadd supergroup
# 验证是否成功
grep supergroup /etc/group
```
#### 2. 将用户添加到supergroup组中
```shell
sudo usermod -a -G supergroup 用户名
# 验证是否成功
id 用户名
```
#### 3. 将上述信息同步到HDFS
```shell
sudo -u hdfs hdfs dfsadmin -refreshUserToGroupsMappings
```
### （四）Hue问题
#### 1. Load Balancer无法启动
```shell
# 安装httpd和mod_ssl后重启Load Balancer
sudo yum -y install httpd mod_ssl
```
#### 2. 配置Hue查看HBase
##### 2.1. 开启HBase Thrift服务
##### 2.2. 修改HBase配置（core-site.xml）
```xml
<property>
	<name>hadoop.proxyuser.hue.hosts</name>
	<value>*</value>
</property>
<property>
	<name>hadoop.proxyuser.hue.groups</name>
	<value>*</value>
</property>
<property>
	<name>hadoop.proxyuser.hbase.hosts</name>
	<value>*</value>
</property>
<property>
	<name>hadoop.proxyuser.hbase.groups</name>
	<value>*</value>
</property>
```
##### 2.3. 修改Hue配置（hue_safety_value）
```p
[hbase]
hbase_conf_dir={{HBASE_CONF_DIR}}
thrift_transport=buffered
```