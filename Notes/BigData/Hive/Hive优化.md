# Hive优化

## 1、SQL语法优化

### 1.1 count(distinct)

* 使用 `SIZE(COLLECT_SET( col ))` 代替 `COUNT(DISTINCT ol)`
* 或者也可使用 `group by` 去重后再做 `count` 操作

### 1.2 order by

* 全局排序，只启用1个reducer，性能低下，即使配置reducer数也不起作用

#### 1.2.1 有limit限制的topN问题

* 使用窗口函数排序取前n的数据做子查询（按具体需求选择排序函数），再使用 `order by` 获取全局排序结果
  * `rank`：排名相同的取相同值，后续排名`会`跳过重复的数量
  * `dense_rank`：排名相同的取相同值，后续排名`不会`跳过重复的数量
  * `row_number`：行号，不管排序字段是否有重复，都按1,2,3,4,……,n排序

#### 1.2.2 没有limit限制的全局排序问题

* 分组内有序的需求下可使用 `distribute by 分组字段 sort by 排序字段` 代替 `order by`
* 全局有序时，正序可使用 `cluster by`（只能正序，不能指定），逆序可使用 `distribute by 排序字段 sort by 排序字段 desc`
* 使用时需要设置reducer数：`set mapreduce.job.reduces=[n];`

## 2、小文件

* 产生原因：
  * 读取的数据源有大量小文件
  * 动态分区插入数据会生成大量小文件
  * reduce数量过多，最终生成文件数与reduce数相同
* 影响：
  * mapper tasks数取决于输入文件个数，小文件过多会启动过多mapper tasks，浪费资源，严重影响性能
  * 每个文件会占用NameNode元数据空间约为150字节，小文件过多会增加NN负担

### 2.1 CombineTextInputFormat

* Hive默认使用 `CombineHiveInputFormat`，会将读取的小文件合并处理，Hadoop默认的 `TextInputFormat` 则不会

### 2.2 配置JVM重用

* 修改 `mapred-site.xml`

```xml
<property>
  <name>mapreduce.job.jvm.numtasks</name>
  <value>10</value>
  <description>How many tasks to run per jvm. If set to -1, there is no limit.</description>
</property>
```

### 2.3 配置map、reduce个数

### 2.4 distribute by控制输出文件数

* 当使用动态分区插入数据时，可使用一下方法控制最终输出的文件数

#### 2.4.1 distribute by [分区字段]

```sql
insert overwrite table xx.xxx partition(dt)
select * from xx.xxxx
distribute by dt;
```

* 会把数据按分区字段（distribute by 字段）分配到不同的reduce下处理。运行每个分区下面只有一个文件

#### 2.4.2 distribute by rand()

```sql
-- 在 map only 任务结束时合并小文件
set hive.merge.mapfiles = true;
-- 在 MR 任务结束时合并小文件
set hive.merge.mapredfiles = true;
-- 作业结束时合并文件的大小
set hive.merge.size.per.task = 256000000;
-- 每个 Map 最大输入大小（决定了合并后文件的数量）
set mapred.max.split.size = 256000000;
-- 每个Reducer的大小，默认1G，输入文件如果是10G，则会起10个reducer
set hive.exec.reducers.bytes.per.reducer=1073741824;

set hive.input.format = org.apache.hadoop.hive.ql.io.CombineHiveInputFormat;

insert overwrite table xx.xxx partition(dt)
select * from xx.xxxx
distribute by rand();
```

* 相较之前的写法，会在每个分区下生成 n 个文件，每个文件都比 256M 大

#### 2.4.3 distribute by rand()*n

```sql
insert overwrite table xx.xxx partition(dt)
select * from xx.xxxx
distribute by cast(rand()*n as int);
```

* 每个分区下最终会输出 n 个大小基本一致的文件，可以人为控制输出的文件个数

### 2.5 使用HAR归档文件

* 以上方法适用于每日跑批任务的定时脚本
* 对已经产生小文件的Hive表可以使用har归档

```sql
set hive.archive.enable = true;
set hive.archive.har.parentdir.settable = true;
set har.partfile.size = 256000000;

alter table xx.xxx archive partition(pt='xxxx-xx-xx');
```
