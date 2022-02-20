# Spark Shuffle 解析

## 一、Hash Shuffle

### 1、普通 Hash Shuffle

1. shuffle write 阶段每个 core 会执行n个task，每个 task 都会对数据按 key 做 hash/numReduce 取模的操作，生成下游 numReduce 个小文件，每个小文件对应下游的一个 task，总文件数 = numTask * numReduce
2. shuffle read task 拉取属于自己的文件进行计算

### 2、优化后的 Hash Shuffle

* 与之前不同的是，shuffle write 阶段每个 core 会创建 numReduce 个文件组，不同 task 数据按 key 做 hash/numReduce 取模将计算结果写入相应的文件组中已有的文件，最终每个文件组形成一个文件，总文件数 = numCore * numReduce

* 2.0版本后已删除

----

## 二、Sort Shuffle

### 1、基础 Sort Shuffle

* 首先会判断shuffle类型，如果不满足启用bypass或序列化的情况，则启用`BaseShuffleHandle`

1. shuffle write task 处理数据会先写入内存，当达到阈值时先对数据按 key 进行排序，然后溢写到磁盘，默认每1w条数据写入一个磁盘临时文件，task 所有数据都处理完后，会将全部的临时文件进行 merge 做合并，另外单独写一个索引文件，用于记录下游各 task 在数据文件中的 start offset 和 end offset，最终每个 task 只生成一个数据文件和一个索引文件
2. 下游 shuffle read task 按照索引文件的记录去数据文件中拉取自己所需的数据

#### 2、 bypass Sort Shuffle

* 满足以下2个条件则启用`BypassMergeSortShuffleHandle`
  1. 该shuffle依赖中没有map端聚合操作（如 groupByKey() 算子）
  2. shuffle read task 数量小于spark.shuffle.sort.bypassMergeThreashold 的值（默认200）
* 与基础版不同的是，在数据溢写时不会按 key 进行排序

#### 3、tungsten-sort shuffle

* 即序列化sort shuffle
* 满足以下3个条件则启用`SerializedShuffleHandle`
  1. 使用的序列化器支持序列化对象的重定位（如KryoSerializer）
  2. shuffle依赖中完全没有聚合操作
  3. 分区数不大于常量MAX_SHUFFLE_OUTPUT_PARTITIONS_FOR_SERIALIZED_MODE的值（最大分区ID号+1，即2^24=16777216）

## 三、参数调优

### 3.1 spark.shuffle.file.buffer

* 默认值：32K
* 说明：用于设置 shuffle write task 溢写磁盘前的缓冲区大小
* 调优：若内存资源充足，可适当调大此参数（如64K），从而减少 shuffle write 过程中的溢写次数，即 `减少磁盘IO`

### 3.2 spark.reducer.maxSizeFlight

* 默认值：48M
* 说明：用于设置 shuffle read task 的缓冲区大小，决定了一次能够拉取多少数据
* 调优：若内存资源充足，可适当调大此参数（如96M），从而减少数据拉取次数，即 `减少网络IO`

### 3.3 spark.shuffle.io.maxRetries

* 默认值：3
* 说明：shuffle read task 拉取数据时，若因网络异常导致失败，则会自动重试，此参数设置最大重试次数
* 调优：对于特别耗时的shuffle操作，可适当增大此参数（如60），避免因JVM的 full gc 或网络不稳定导致的数据拉取失败。对数十上百亿数据的 shuffle 过程，能大幅提高稳定性

### 3.4 spark.shuffle.io.retryWait

* 默认值：5s
* 说明：配合 3.3 参数，此参数设置每次重试的等待间隔
* 调优：建议增大间隔时间（如60s），提高 shuffle 的稳定性

### 3.5 spark.shuffle.memoryFraction

* 默认值：0.2
* 说明：executor 拉取数据后，shuffle read task 进行聚合操作能够使用的内存比例
* 调优：若资源充足且很少使用持久化，则可调大此参数，避免聚合过程中由于内存不足，频繁读写磁盘，性能可提高10%左右

### 3.6 spark.shuffle.manager

* 默认值：sort
* 说明：用于设置 shuffle 的类型，可选值有 hash、sort、tungsten-sort
* 调优：若业务逻辑不需要对数据进行排序，建议通过后面的参数启用 bypass 机制，或者启用 hash shuffle

### 3.7 spark.shuffle.sort.bypassMergeThreshold

* 默认值：200
* 说明：若 shuffle 过程使用的是非聚合型算子，且 shuffle read task 数小于此参数，则 shuffle write 过程中溢写之前不会对数据进行排序
* 调优：若业务不需要对数据进行排序，则可适当调大此参数，减少排序过程的性能开销

### 3.8 spark.shuffle.consolidateFiles

* 默认值：false
* 说明：使用 hash shuffle 时此参数生效，设置为 true 时，会启用 consolidate 机制，大幅合并 shuffle write 的输出文件
* 调优：若业务不需对数据排序，除了 bypass 机制外，还可以使用 hash shuffle 同时启用 consolidate 机制，比开启 bypass 的 sort shuffle 性能要高 10%~30%
