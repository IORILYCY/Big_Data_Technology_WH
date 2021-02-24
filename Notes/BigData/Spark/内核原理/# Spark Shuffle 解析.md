# Spark Shuffle 解析

## 一、Hash Shuffle

### 1、普通 Hash Shuffle

1. shuffle write 阶段每个 core 会执行n个task，每个 task 都会对数据按 key 做 hash/numReduce 取模的操作，生成下游 numReduce 个小文件，每个小文件对应下游的一个 task，总文件数 = numTask * numReduce
2. shuffle read task 拉取属于自己的文件进行计算

### 2、优化后的 Hash Shuffle

* 与之前不同的是，shuffle write 阶段每个 core 会创建 numReduce 的文件组，不同 task 数据按 key 做 hash/numReduce 取模将计算结果写入相应的文件组中已有的文件，最终每个文件组形成一个文件，总文件数 = numCore * numReduce

----

## 二、Sort Shuffle

### 1、普通 Sort Shuffle

1. shuffle write task 处理数据会先写入内存，当达到阈值时先对数据按 key 进行排序，然后溢写到磁盘，默认每1w条数据写入一个磁盘临时文件，task 所有数据都处理完后，会将全部的临时文件进行 merge 做合并，另外单独写一个索引文件，用于记录下游各 task 在数据文件中的 start offset 和 end offset，最终每个 task 只生成一个数据文件和一个索引文件
2. 下游 shuffle read task 按照索引文件的记录去数据文件中拉取自己所需的数据

### 2、bypass Sort Shuffle

* 前提：1. 非聚合类算子（如 reduceByKey） 2. shuffle read task 数量小于spark.shuffle.sort.bypassMergeThreashold 的值（默认200）
* 与普通版不同的是，在数据溢写时不会对 key 进行排序

## 三、参数调优
