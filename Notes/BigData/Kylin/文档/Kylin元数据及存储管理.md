# 001_Kylin元数据及存储管理

---
## 一、元数据管理
* 查看实际参与与计算的Cuboid
```bash
./bin/kylin.sh org.apache.kylin.engine.mr.common.CubeStatsReader ${CUBE_NAME}
```
### 1、元数据路径
* Kylin使用 `resource root path + resource name + resource suffix` 作为key值(HBase中的rowkey)来存储元数据。

Resource root path | resource name | resource suffix
:-|:-|:-
/cube | /cube name | .json
/cube_desc | /cube name | .json
/cube_statistics | /cube name/uuid | .seq
/model_desc | /model name | .json
/dict | /DATABASE.TABLE/COLUMN/uuid | .dict
/project | /project name | .json
/table_snapshot | /DATABASE.TABLE/uuid | .snapshot
/table | /DATABASE.TABLE–project name | .json
/table_exd | /DATABASE.TABLE–project name | .json
/execute | /job id | 
/execute_output | /job id-step index | 
/kafka | /DATABASE.TABLE | .json
/streaming | /DATABASE.TABLE | .json
/user | /user name | 
### 2、查看原数据
* Kylin以二进制字节的格式将元数据存储在HBase中，查看元数据可运行如下命令：
1. 查看所有元数据
```bash
./bin/metastore.sh list /path/to/store/metadata
```
2. 查看某个实体数据
```bash
./bin/metastore.sh cat /path/to/store/entity/metadata
```
### 3、备份元数据
1. 全量备份
```bash
./bin/metastore.sh backup
```
* 元数据将被分到 `KYLIN_HOME/metadata_backps` 下，它的命名规则使用了当前时间作为参数：KYLIN_HOME/meta_backups/meta_year_month_day_hour_minute_second 
2. 选择备份
```bash
# 获取所有的cube desc元数据
./bin/metastore.sh fetch /cube_desc/

# 导出单个cube desc的元数据
./bin/metastore.sh fetch /cube_desc/${CUBE_NAME}.json
```
### 4、恢复原数据
1. 重置元数据

    <font color=#DC143C>此操作会清理HBase上所有的元数据，慎重操作并提前做好备份！！！</font>
```bash
./bin/metastore.sh reset
```
2. 上传备份的元数据到 Kylin 的 metadata store
```bash
./bin/metastore.sh restore ${KYLIN_HOME}/meta_backups/meta_xxxx_xx_xx_xx_xx_xx
```
3. 单击 Web UI 上 System 面板下 `Reload Metadata` 按钮刷新缓存
### 5、有选择地恢复元数据（推荐）
1. 创建新的存储路径，根据要还原的元数据文件的位置在其中创建子目录
* 可参考前面的元数据路径
2. 将要恢复的元数据复制到新路径下，手动修改元数据
3. 从新路径恢复元数据，此时只有该路径下的文件才会上传到元数据库
```bash
./bin/metastore.sh restore /path/to/restore_new
```
4. 单击 Web UI 上 System 面板下 `Reload Metadata` 按钮刷新缓存
### 5、清理无用元数据
1. 检查元数据
```bash
# 此命令不会删除任何数据
# jobThreshold参数可以设定要保留的元数据天数，默认30
./bin/metastore.sh clean --jobThreshold 30
```
2. 清理元数据（记得先备份）
```bash
# 添加--delete true参数确认删除
./bin/metastore.sh clean --delete true --jobThreshold 30
```
## 二、存储管理
* Kylin 在构建 cube 期间会产生 Hive 中间表，也会在 HDFS 上生成中间文件；除此之外，当清理/删除/合并 cube 时，一些 HBase 表可能被遗留在 HBase 却再也不会被查询；可以定期做离线的存储清理确保这些数据不会影响系统性能
1. 检查可清理的资源
```bash
# 此命令不会删除任何数据
./bin/kylin.sh org.apache.kylin.tool.StorageCleanupJob --delete false
```
2. 删除上述资源
```bash
# 修改delete参数为true确认删除
./bin/kylin.sh org.apache.kylin.tool.StorageCleanupJob --delete true
```
* 完成后，Hive 里的中间表, HDFS 上的中间文件及 HBase 中的 HTables 都会被移除
3. 删除所有资源
```bash
# 添加--force true参数删除全部数据
./bin/kylin.sh org.apache.kylin.tool.StorageCleanupJob \
--force true --delete true
```
* 完成后，Hive 中所有的中间表, HDFS 上所有的中间文件及 HBase 中的 HTables 都会被移除