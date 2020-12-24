# 003_CDH集成Kylin

---
* 下载地址：[下载CDH5版本Kylin](http://kylin.apache.org/cn/download/)
* [官方文档](http://kylin.apache.org/cn/docs/gettingstarted/kylin-quickstart.html)
## 一、安装启动
### 1. 上传并解压下载的tar包
```bash
tar -zxvf apache-kylin-2.6.4-bin-cdh57.tar.gz -C /opt/cdh-5.15.2
mv apache-kylin-2.6.4-bin-cdh57 kylin-2.6.4
```
### 2. 配置环境变量
* 注意：Spark作为Kylin启动的一项环境检查，无论是否使用Spark作为Kylin的构建引擎，都需要集群安装Spark
```bash
sudo vim /etc/profile

# SPARK_HOME
export SPARK_HOME=/opt/cdh-5.15.2/cloudera/parcels/SPARK2/lib/spark2
export PATH=$PATH:$SPARK_HOME/sbin

# KYLIN_HOME
export KYLIN_HOME=/opt/cdh-5.15.2/kylin-2.6.4
export PATH=$PATH:$KYLIN_HOME/bin
```
```bash
# 环境变量生效
source /etc/profile
```
### 3. 修改配置文件
```bash
vim $KYLIN_HOME/conf/kylin.properties

# 修改：
kylin.server.cluster-servers=192.168.1.120:7070
# 增加：
kylin.job.jar=$KYLIN_HOME/lib/kylin-job-2.6.4.jar
kylin.coprocessor.local.jar=$KYLIN_HOME/lib/kylin-coprocessor-2.6.4.jar
kylin.job.yarn.app.rest.check.status.url=http://192.168.1.57:8088/ws/v1/cluster/apps/{job_id}?anonymous=true
```
* 配置文件中有详细说明，此处不一一列举
### 4. 执行环境检查
```bash
sudo -u hdfs $KYLIN_HOME/bin/check-env.sh
```
* CDH集群会为组件创建独立的用户，此处如使用错误用户会报HDFS权限错误，解决方法即将用户添加到supergroup组中，具体方法在`CDH5.15的安装`中已写明，此处不再赘述
### 5. 启动服务
```bash
$KYLIN_HOME/bin/kylin.sh start
$KYLIN_HOME/bin/kylin.sh stop
```
* 没有`restart`

---
## 二、登录Web页面
* 地址：http://host:7070/kylin
+ 默认账号
    - 管理：ADMIN / KYLIN
    - 建模：MODELER / MODELER
    - 分析：ANALYST / ANALYST
* 默认账号需要在Web页面登陆一次后才能正常使用

---
## 三、其他配置
### （一）配置Impala为下压查询引擎
#### 1. 修改kylin.properties
```properties
kylin.query.pushdown.runner-class-name=org.apache.kylin.query.adhoc.PushDownRunnerJdbcImpl
kylin.query.pushdown.jdbc.url=jdbc:impala://host:21050/default
kylin.query.pushdown.jdbc.driver=com.cloudera.impala.jdbc41.Driver
# 如未配置用户认证，用户可用任意有hdfs权限的系统用户
kylin.query.pushdown.jdbc.username=hadoop
# kylin.query.pushdown.jdbc.password=
kylin.query.pushdown.jdbc.pool-max-total=150
kylin.query.pushdown.jdbc.pool-max-idle=100
kylin.query.pushdown.jdbc.pool-min-idle=50
```
#### 2. 上传Impala的JDBC驱动
* 下载地址：[下载Impala的JDBC](https://www.cloudera.com/downloads/connectors/impala/jdbc/2-6-12.html/)
* 解压下载的zip包，上传`ImpalaJDBC41.jar`到`$KYLIN_HOME/lib`下，重启Kylin
### （二）配置Presto为下压查询引擎
#### 1. 修改kylin.properties
```properties
kylin.query.pushdown.runner-class-name=org.apache.kylin.query.adhoc.PushDownRunnerJdbcImpl
kylin.query.pushdown.jdbc.url=jdbc:presto://coordinator-host:port/hive
kylin.query.pushdown.jdbc.driver=com.facebook.presto.jdbc.PrestoDriver
# 如未配置用户认证，用户可用任意有hdfs权限的系统用户
kylin.query.pushdown.jdbc.username=hadoop
# kylin.query.pushdown.jdbc.password=
kylin.query.pushdown.jdbc.pool-max-total=150
kylin.query.pushdown.jdbc.pool-max-idle=100
kylin.query.pushdown.jdbc.pool-min-idle=50
```
#### 2. 上传Impala的JDBC驱动
* 下载地址：[下载Presto的JDBC](http://prestodb.github.io/download.html)
* 上传`presto-jdbc-0.228.jar`到`$KYLIN_HOME/lib`下，重启Kylin
### （三）修改压缩算法
* Kylin默认使用Snappy压缩，可通过配置文件修改为lzo、gzip、lz4、none
* 修改kylin.properties
```properties
# 修改为lzo压缩
kylin.storage.hbase.compression-codec=lzo
```
* 需要集群支持LZO压缩，方法在`CDH5.15的安装`中已写明，此处不再赘述

---
## 四、注意事项
### （一）HDFS权限报错
* 解决办法：将Kylin的启动账户添加到supergroup组中，具体操作见`CDH5.15的安装`
### （二）关于下压查询
1. Impala-2.12不支持date类型，在使用Impala为下压查询引擎时，时间字段不要使用date类型
2. Presto查询使用的varchar类型与Kylin不兼容，在使用Presto为下压查询引擎时，建议使用string作为字符串类型
3. Kylin官方在3.1.0版正式加入了对Presto的支持
4. 2.6.4版本在下压含`avg()`的SQL时，如没有配置对应model会报异常，2.6.5版已修复

---
## 五、系统Cube的创建&监控面板启用
### 1. 创建配置文件
* 在`$KYLIN_HOME`目录下创建一个配置文件`SCSinkTools.json`。例如：
```json
[
    {
       "sink": "hive",
       "storage_type": 2,
       "cube_desc_override_properties": {
         "kylin.cube.algorithm": "INMEM",
         "kylin.cube.max-building-segments": "1"
       }
    }
]
```
### 2. 生成 Metadata
* 在`$KYLIN_HOME`文件夹下运行以下命令生成相关的 metadata：
```bash
mkdir -p system_cube

./bin/kylin.sh org.apache.kylin.tool.metrics.systemcube.SCCreator \
-inputConfig SCSinkTools.json \
-output system_cube
```
### 3. 建立数据源
* 运行下列命令生成 Hive 源表：
```bash
hive -f system_cube/create_hive_tables_for_system_cubes.sql
```
### 4. 为系统 Cubes 上传 Metadata
* 通过下列命令上传 metadata 到 hbase：
```bash
./bin/metastore.sh restore system_cube
```
### 5. 重载 Metadata
* 在 Kylin web UI 重载 metadata。然后，一组系统 Cubes 将会被创建在系统 project 下，即 `KYLIN_SYSTEM`
### 6. 定期构建系统 Cube
#### 6.1. 创建构建脚本
```bash
#!/bin/bash

dir=$(dirname ${0})
export KYLIN_HOME=${dir}/../

CUBE=$1
INTERVAL=$2
DELAY=$3
CURRENT_TIME_IN_SECOND=`date +%s`
CURRENT_TIME=$((CURRENT_TIME_IN_SECOND * 1000))
END_TIME=$((CURRENT_TIME-DELAY))
END=$((END_TIME - END_TIME%INTERVAL))

ID="$END"
echo "building for ${CUBE}_${ID}" >> ${KYLIN_HOME}/logs/build_trace.log
sh ${KYLIN_HOME}/bin/kylin.sh org.apache.kylin.tool.job.CubeBuildingCLI --cube ${CUBE} --endTime ${END} > ${KYLIN_HOME}/logs/system_cube_${CUBE}_${END}.log 2>&1 &
```
#### 6.2. 创建定时任务自动构建
```bash
0 */2 * * * sh ${KYLIN_HOME}/bin/system_cube_build.sh KYLIN_HIVE_METRICS_QUERY_QA 3600000 1200000

20 */2 * * * sh ${KYLIN_HOME}/bin/system_cube_build.sh KYLIN_HIVE_METRICS_QUERY_CUBE_QA 3600000 1200000

40 */4 * * * sh ${KYLIN_HOME}/bin/system_cube_build.sh KYLIN_HIVE_METRICS_QUERY_RPC_QA 3600000 1200000

30 */4 * * * sh ${KYLIN_HOME}/bin/system_cube_build.sh KYLIN_HIVE_METRICS_JOB_QA 3600000 1200000

50 */12 * * * sh ${KYLIN_HOME}/bin/system_cube_build.sh KYLIN_HIVE_METRICS_JOB_EXCEPTION_QA 3600000 12000
```
### 7. 使用官方脚本创建
* 2.6.0版后官方提供了脚本自动创建系统cube，如下：
```bash
# 创建系统 Cube：
sh system-cube.sh setup
# 构建系统 Cube：
sh bin/system-cube.sh build
# 为系统 Cube 添加定时任务：
sh bin/system.sh cron
```
### 8. 启用Dashboard
* 修改kylin.properties
```properties
kylin.web.dashboard-enabled=true
```
* 重启服务后可在 Web UI 看到 `Dashboard` 面板