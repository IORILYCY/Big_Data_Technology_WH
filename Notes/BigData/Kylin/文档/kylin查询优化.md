# Kylin查询优化

Kylin查询的声明周期分为以下三个阶端，可按阶段分析查询性能瓶颈并优化。

## 1 第一阶段：SQL解析

* 在收到SQL请求后，Kylin Query Server会调用Calcite对SQL语句进行解析
  1. 首先，Calcite会将SQL语句通过范式编译器解析为一颗抽象语义树（AST）
  2. 然后Calcite对这棵AST树进行优化，将Project（select部分）和Filter（where部分）Push down至Hadoop集群
  3. 接着定义implement plan，共有两种方式：HepPlanner（启发式优化）和VolcanoPlanner（基于代价的优化）

## 2 第二阶段：SQL查询

* 针对子查询，UNION等场景，Calcite将SQL分解为多个OLAPContext，同时执行Filter Pushdown和Limit Pushdown等优化手段，然后提交到HBase上执行

## 3 第三阶段：数据集中和聚合

* HBase上的查询任务执行完成后，数据返回至Kylin Query Server端，由Calcite聚合多个OLAP Context的查询结果后，最后返回给前端BI
* Kylin中的一个hbase表（即一个segment）对应一个coprocessor，查询过程中会先发送一个request到一个regionserver上，然后HBase会把该表的数据都拉到这个regionserver上，使用coprocessor进行聚合运算

## 4 优化手段

### 4.1 合理设计RowKey

* Cube 的最大物理维度数量 (不包括衍生维度) 是 63，但是不推荐使用大于 30 个维度的 Cube，会引起维度灾难
* 合理调整RowKey中维度的排列顺序，原则是把过滤字段（例如PART_DT等日期型字段）和高基维（例如BUYER_ID，SELLER_ID等客户字段）放在Rowkey的前列，这样能够显著提升【第二阶段SQL查询】在HBase上数据扫描和I/O读取的效率
* 同时可有针对性的选择不同维度的编码方式，以及按照高基维度对Cube分片减少扫描的数据量

### 4.2 重写SQL

* Kylin遵循的是“Scatter and gather”模式，而有的时候在【第二阶段SQL查询】时无法实现Filter Pushdown和Limit Pushdown等优化手段，需要等待数据集中返回Kylin后再筛选数据，这样数据吞吐量会很大，影响查询性能，需要重写SQL语句
* 与Hive不同，要减少查询的数据量，此时就需要实现谓词下推，要减少使用子查询，将筛选条件都写到where条件中

### 4.3 优化聚合组

* 通过查看后台日志，可以知道查询命中的聚合组，由于Cuboid的维度越多，数据量越大，查询性能越差，需要有针对性的设置聚合组，降低膨胀率
* 应尽量按照具体的查询维度特点来减少聚合组的维度数量，并合理运用必要维度、层次维度和联合维度
* 必要维度即查询中必然会出现在where或group by中的维度
* 层级维度通常具有逻辑层次关系，如年月日、国家地区等
* 联合维度可能有id与value的映射关系，也可以将多个低基维度（每个维度不超过10，总的乘积不超过10000）合并为一个联合维度
* 对于基数特别大的高基维度，可以将它和会与其同时被查询的维度单独放到一个聚合组中，以降低Cube的膨胀率
* 对于数据量比较小的维度表，可以选择使用衍生维度，衍生维度不会参与Cube计算，可有效降低Cube大小，但会在查询时进行实时聚合

### 4.4 并发粒度优化

* 构建引擎根据Segment估计的大小，以及参数“kylin.hbase.region.cut”的设置决定Segment在存储引擎中总共需要几个分区来存储，如果存储引擎是HBase，那么分区数量就对应HBase中的Region的数量
* 通过修改Cube的配置参数：kylin.hbase.region.cut、kylin.hbase.region.count.min（默认为1）kylin.hbase.region.count.max（默认为500）来控制Segment分区的大小，以及每个Segment最少或最多可以被分成多少个分区

### 4.5 提高Server性能

* 从Kylin Query Server处理效率角度，需要实时监控Kylin节点的CPU占有率和内存消耗，如果两者很高的话可能导致【第一阶段SQL解析】的效率下降，需要增加Kylin节点CPU和JVM配置
* 修改setenv.sh中的KYLIN_JVM_SETTINGS配置项

### 4.6 降低网络延迟

* 监控BI前端，Kylin Query Server节点和Hadoop集群之间的网络通信状态，大数据集传输可能引起网络堵塞，尤其是在多并发查询的情况下更容易发生网络堵塞，进而对查询性能产生显著影响

### 4.7 将数据处理放在ETL阶段

* 对于一些复杂的SQL语句，如果包含子查询的话，尽量避免Left Join操作，尤其是Join的两个数据集都较大的情况下，会对查询性能有显著的影响
