# Spark SQL 优化

## 1、内存优化

### 1.1 RDD

* RDD 默认 cache()（调用persist()）的缓存级别为 MEMORY_ONLY，性能最高，但是内存消耗较大
* 当内存资源不充足而CPU资源充足的情况下，可以使用 kryo 序列化 + MEMORY_ONLY_SER 缓存级别减少内存消耗，但是会增加CPU的负载

```scala
# 1 新建 SparkConf
val sparkConf = new SparkConf().setAppName("test")
        # 2 SparkConf 配置序列化类为 Kryo
        .set("spark.serializer", "org.apache.spark.serializer.KryoSerializer")
        # 3 注册需要序列化的自定义类
        .registerKryoClasses(Array(classOf[CoursePay]))
```
