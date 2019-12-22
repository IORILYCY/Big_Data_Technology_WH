# 002_CDH集成Presto

---
<font color=#DC143C>Presto的基本环境：
Linux或Mac OS X
Java 8,64位（小版本151以上）
Python 2.4+
</font>

---
## 一、 安装Presto
* 下载地址：[下载Presto](https://prestodb.github.io/download.html)
### 1. 上传文件并解压到${CM}/cloudera/parcels
```shell
tar -zxvf presto-server-0.216.tar.gz -C /opt/cloudera/parcels/
```
### 2. 为Presto创建软连接
```shell
# 创建软连接
sudo ln -s presto-server-0.228 PRESTO
# 更改权限
sudo chown cloudera-scm:cloudera-scm PRESTO presto-server-0.228
```
### 3. 为Presto指定JDK
```shell
sudo vim ${PRESTO_HOME}/bin/launcher
# 添加：
export JAVA_HOME=/usr/java/jdk1.8
export PATH=$PATH:$JAVA_HOME/bin
```
### 4. 创建配置文件
* 在presto根目录下创建etc文件夹，并在etc下创建配置文件
```shell
mkdir -p etc
```
#### 4.1. 创建node.properties
* 节点属性配置
+ Presto集群分为两种节点：
	- coordinator：作为主节点提供连接服务并下发、执行任务
	- worker：只能执行具体任务
```shell
vim node.properties
#
# 集群名称，不能包含特殊字符如“-”
node.environment=presto-cluster
# 节点ID，节点间不能相同
node.id=presto-cdh001
# presto的数据路径
node.data-dir=/opt/data/presto
```
#### 4.2. 创建jvm.config
* Java虚拟机配置
```shell
vim jvm.config
#
-server
-Xmx8G
-XX:+UseG1GC
-XX:G1HeapRegionSize=32M
-XX:+UseGCOverheadLimit
-XX:+ExplicitGCInvokesConcurrent
-XX:+HeapDumpOnOutOfMemoryError
-XX:+ExitOnOutOfMemoryError
```
#### 4.3. 创建log.properties
* 日志输出配置
```shell
vim log.properties
#
# INFO / WARN / ERROR
com.facebook.presto=INFO
```
#### 4.4. 创建config.properties
* 服务配置
1. coordinator节点
```shell
vim config.properties
#
coordinator=true
node-scheduler.include-coordinator=true
http-server.http.port=8090
query.max-memory=4GB
query.max-memory-per-node=1GB
discovery-server.enabled=true
discovery.uri=http://10.18.100.116:8090
```
2. worker节点
```shell
vim config.properties
#
coordinator=false
http-server.http.port=8090
query.max-memory=4GB
query.max-memory-per-node=1GB
discovery.uri=http://10.18.100.116:8090
```
### 5. 配置catalog
* 在etc下创建catalog文件夹
#### 5.1. Hive连接配置
```shell
vim hive.properties
#
# 连接名hive-hadoop2不可修改
connector.name=hive-hadoop2
hive.metastore.uri=thrift://10.18.100.115:9083
```
#### 5.2. MySQL连接配置
```shell
vim mysql.properties
#
connector.name=mysql
connection-url=jdbc:mysql://10.18.100.115:3306
connection-user=root
connection-password=root
```
### 6. 启动Presto服务
```shell
# 启动
/opt/cloudera/parcels/presto/bin/launcher start
# 停止
/opt/cloudera/parcels/presto/bin/launcher start
```
* 启动后登录`http://coordinator:port`，可查看Presto的运行状态

---
## 二、安装yanagishima作为Presto的Web UI
* 下载地址：[下载对应版本的zip包](https://github.com/yanagishima/yanagishima)
* 或者使用git下载自行打包
```shell
git clone https://github.com/yanagishima/yanagishima.git
cd yanagishima
git checkout -b [version] refs/tags/[version] ./gradlew distZip
```
### 1. 上传zip包并解压
```shell
unzip yanagishima-20.0
```
### 2. 修改配置文件
```shell
cd yanagishima-20.0
vim conf/yanagishima.properties
```
```properties
# yanagishima web port
jetty.port=7080
# 30 minutes. If presto query exceeds this time, yanagishima cancel the query.
presto.query.max-run-time-seconds=1800
# 1GB. If presto query result file size exceeds this value, yanagishima cancel the query.
presto.max-result-file-byte-size=1073741824
# you can specify freely. But you need to specify same name to presto.coordinator.server.[...] and presto.redirect.server.[...] and catalog.[...] and schema.[...]
presto.datasources=presto
auth.presto=false
# presto coordinator url
presto.coordinator.server.presto=http://10.18.100.116:8090
# almost same as presto coordinator url. If you use reverse proxy, specify it
presto.redirect.server.presto=http://10.18.100.116:8090
# presto catalog name
catalog.presto=hive
# presto schema name
schema.presto=default
# if query result exceeds this limit, to show rest of result is skipped
select.limit=500
# http header name for audit log
audit.http.header.name=some.auth.header
use.audit.http.header.name=false
# limit to convert from tsv to values query
to.values.query.limit=500
# authorization feature
check.datasource=false
hive.jdbc.url.hive=jdbc:hive2://10.18.100.115:10000/default;auth=noSasl
hive.jdbc.user.hive=yanagishima
hive.jdbc.password.hive=yanagishima
hive.query.max-run-time-seconds=3600
hive.query.max-run-time-seconds.hive=3600
resource.manager.url.hive=http://10.18.100.115:8088
sql.query.engines=presto
hive.datasources=hive
hive.disallowed.keywords.hive=insert,drop
# 1GB. If hive query result file size exceeds this value, yanagishima cancel the query.
hive.max-result-file-byte-size=1073741824
hive.setup.query.path.hive=/usr/local/yanagishima/conf/hive_setup_query_hive
cors.enabled=false
```
### 3. 启动服务
```shell
# 启动
nohup bin/yanagishima-start.sh >/dev/null 2>&1 &
# 停止
bin/yanagishima-shutdown.sh
```
* 启动后登陆`http://10.18.100.116:7080`进行查询灯操作
* 注意：SQL语句不要带`;`