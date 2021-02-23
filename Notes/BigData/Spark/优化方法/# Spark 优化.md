# Spark 优化
## 1、缓存重复使用的RDD

## 2、broadcast+map 代替join
* 适用前提：广播的rdd较小

## 3、尽量少用shuffle算子
groupByKey、reduceByKey、aggregateByKey、join、distinct、repartition

## 4、使用预聚合类算子
reduceByKey代替groupByKey

## 5、使用高性能算子
1. reduceByKey代替groupByKey
2. mapPartition代替map
3. foreachPartition代替foreach
4. filter后使用coalesce
5. 使用repartitionAndSortWithPartition代替repartition+sort

## 6、广播大变量

## 7、kryo序列化
* 使用序列化的场景：
    1. 使用外部变量会将其序列化后网络传输
    2. 自定义类型作为RDD泛型，所有对象都会序列化
    3. 序列化持久策略

* 使用步骤：SparkConf配置序列化类，然后注册需要序列化的自定义类

## 8、参数调优
1. --num-executor：50-100
2. --executor-memory：4g-8g
* num-executor * executor-memory小于队列总资源的1/3~1/2，避免过多占用内存，影响其他任务
3. --executor-cores：2-4，每个CPU core同时只能运行一个task
* num-executor * executor-cores小于队列总资源的1/3~1/2
4. --driver-memory：1g
5. --conf spark.default.parallelism：500-1000，每个stage默认的task数量，不配置默认一个HDFS block对应一个task。建议配置为num-executor * executor-cores的2~3倍
6. --conf spark.storage.memoryFraction：RDD持久化占用Executor内存的比例，默认0.6
7. --conf spark.shuffle.memoryFraction：shuffle过程中task拉去上游task输出后，进行聚合操作时能够使用Executor内存的比例，默认0.2
* 根据作业中持久化与shuffle的多少来调整前面两个参数

## 9、数据倾斜
* 原因：shuffle过程中某个key的数据量过大，全部进入一个task处理，导致作业运行很慢。
* 代码定位：只会发生在shuffle过程中，根据算子确定，groupByKey、reduceByKey、aggregateByKey、join、distinct、repartition
* 某个task运行特别慢：
    1. 查看日志确定发生数据倾斜的stage
    2. 根据stage划分原理推断具体代码位置，必有shuffle算子
* 某个task莫名内存溢出：
    1. 查看日志中的异常栈，确认代码位置，有shuffle算子则数据倾斜
    2. 需要配合查看task处理时间和处理数据量，不能单纯因内存溢出判断数据倾斜
* 查看key分布：
    1. SparkSQL的group by、join，查看数据表的key分布
    2. shuffle算子，rdd.countByKey()计算分布，collect到客户端打印查看
### 9.1 解决方案
#### 9.1.1 Hive ETL预处理
* 将倾斜逻辑在Hive中先处理，Spark再讲预处理后的新表作为数据源执行后续操作
#### 9.1.2 过滤少数导致倾斜的key
* 如果只有少数key导致倾斜，且对计算本身影响不大的情况下，可以先进行采样，计算样本中数据量大的key，然后将对应数据过滤掉不处理
* 只适用于倾斜key无意义或影响不大的情况
#### 9.1.3 提高shuffle并行度
* 只是将倾斜key分到了更多的task上，指标不治本，本质上还是数据倾斜的
#### 9.1.4 两阶段聚合
* 仅适合聚合计算场景，如reduceByKey算子或SQL中group by操作时
* 先对key打上随机数前缀做局部聚合，再将前缀去掉做全局聚合
#### 9.1.5 将reduce join转为map join
* 不使用join算子，将较小的rdd用collect拉倒driver，再使用broadcast进行广播，对另一个rdd用map算子判断两个rdd的join key相等再做处理，实现join操作
* 只适用于大表join小表，不适用于大表join大表的情况
#### 9.1.6 采样倾斜key，拆分join
* 适用于大表join大表时少量key引起倾斜的情况
1. 使用sample算子采样，统计每个key数量判断倾斜key
2. 将倾斜key数据拆分出来，给每个key都打上随机数前缀，形成单独的rdd，其余key形成普通的rdd
3. 另一张表的倾斜key也拆分出来，每条数据都打上0~n的随机数前缀，形成单独的rdd，其余key形成普通的rdd
4. 将两个带前缀rdd做join，两个不带前缀rdd做join
5. 将两个join结果union结合
* 若倾斜key较多，则此方法不适用
#### 9.1.7 随机前缀和扩容join
* 操作方法与方法6相同，不同的是不拆分倾斜key，而是将所有数据都打上随机前缀和扩容
* 可处理join类型引起的倾斜，但更多的是缓解，对内存要求高
