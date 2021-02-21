# Spark Shuffle 解析
## 一、Hash Shuffle
### 1、普通 Hash Shuffle
1. map 阶段每个 core 中运行的每一个 task 都会对数据按 key 做 hash/numReduce 取模的操作，生成下游 reduce task数 的小文件，总文件数 = map task数 * reduce task数
2. reduce 阶段拉去属于自己文件进行计算
### 2、优化后的 Hash Shuffle
* 与之前不同的是，map 阶段每个 core 会创建 reduce task数 的缓存，不同 task 数据按 key 做 hash/numReduce 取模将计算结果存入相应的缓存中，全部 task 执行完毕后将缓存落盘，总文件数 = reduce task数

----

## 二、Sort Shuffle
### 1、普通 Sort Shuffle

### 2、bypass Sort Shuffle
