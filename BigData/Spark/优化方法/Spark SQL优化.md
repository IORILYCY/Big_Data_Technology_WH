# Spark SQL 优化

## 1、内存优化

### 1.1 RDD

* RDD 默认 cache()（调用persist()）的缓存级别为 MEMORY_ONLY，性能最高，但是内存消耗较大
* 当内存资源不充足而CPU资源充足的情况下，可以使用 kryo 序列化 + MEMORY_ONLY_SER 缓存级别减少内存消耗，但是会增加CPU的负载
* 序列化占用内存约为未序列化的 1/3

```scala
// 1 新建 SparkConf
val sparkConf = new SparkConf().setAppName("test")
    // 2 SparkConf 配置序列化类为 Kryo
    .set("spark.serializer", "org.apache.spark.serializer.KryoSerializer")
    // 3 注册需要序列化的自定义类
    .registerKryoClasses(Array(classOf[CoursePay]))
val session = SparkSession.builder().config(sparkConf).enableHiveSupport().getOrCreate()
……
// rdd.cache()
rdd.persist(StorageLevel.MEMORY_ONLY_SER)
```

### 1.2 DataSet/DataFrame

* DataFrame 的实现是 Row 类型的 DataSet，DataSet 的默认 cache()（persist() -> cacheQuery()） 的缓存级别为 MEMORY_AND_DISK
* 序列化方法既不是 Java 也不是 Kryo，而是一种特殊的编码格式，且序列化后占用内存与未序列化时相差不大
* 开发中建议使用 DataFrame/DataSet

## 2、分区和参数控制

* 参数 `spark.sql.shuffle.partitions` 可控制 Spark sql、DataFrame、DataSet 的 shuffle 分区个数（默认200），但不能控制 RDD 的分区数

  1. 在默认情况下，多表 join 后会输出200个小文件
  2. 为此需要在Spark最终落盘前，减少分区数，可使用 coalesce 算子实现，需要注意 coalesce 的参数必须必原有的分区数小，否则无效
  3. 为了充分利用 CPU 资源，通常需要将 task 数，即分区数设置为 core 数的 2~3 倍

```bash
spark-submit \
--master yarn \
--deploy-mode cluster \
--driver-memory 1g \
--num-executors 3 \
--executor-cores 4 \
--executor-memory 4g \
--queue spark \
--conf spark.sql.shuffle.partitions=36 \
--conf spark.default.parallelism=36 \
# --conf spark.storage.memoryFraction= \
# --conf spark.shuffle.memoryFraction= \
--class com.empl.sparksql.Test \
spark-sql-test-1.0-SNAPSHOT-jar-with-dependencies.jar
```

## 3、广播join

* 大表 join 小表时，可以将小表 broadcast 聚合到 Driver，然后再分发到 Executor 做 join，广播 Join 默认小表大小为10M，由参数 `spark.sql.autoBroadcastJoinThreshold` 控制
* 可直接规避掉 shuffle

1. 通过参数优化

    ```scala
    val sparkConf = new SparkConf().setAppName("test")
        // .set("spark.sql.autoBroadcastJoinThreshold", "-1") // 禁用自动 broadcast hash join
        .set("spark.sql.autoBroadcastJoinThreshold", "10485760") // 默认10M
    val session = SparkSession.builder().config(sparkConf).enableHiveSupport().getOrCreate()
    ```

2. 通过 API 调用

```scala
val sparkConf = new SparkConf().setAppName("test")
    // .set("spark.sql.autoBroadcastJoinThreshold", "-1") // 禁用自动 broadcast hash join
val session = SparkSession.builder().config(sparkConf).enableHiveSupport().getOrCreate()

import org.apache.spark.sql.functions._
broadcast(ds1).join( ds2, Seq("col1", "col2"), "joinType" ).drop( "col1", "col2" )
```

## 4、数据倾斜

### 4.1 广播Join

* 将小表广播后再进行 join，操作方法如前所述

### 4.2 打散大表，扩容小表

1. 打散大表：实际就是数据一进一出进行处理，对 key 前拼上随机前缀实现打散
2. 扩容小表：实际就是将 DataFrame 中每一条数据，转成一个集合，并往这个集合里循环添加10条数据，最后使用flatmap压平此集合，达到扩容的效果

```scala
// 将大表打散，打散10份
val newCourseShoppingCart = courseShoppingCart.mapPartitions((partitions: Iterator[Row]) => {
    partitions.map(item => {
    val courseid = item.getAs[Int]("courseid")
    val randInt = Random.nextInt(10)

    DwdCourseShoppingCart(courseid, item.getAs[String]("orderid"),
        item.getAs[String]("coursename"), item.getAs[java.math.BigDecimal]("cart_discount"),
        item.getAs[java.math.BigDecimal]("sellmoney"), item.getAs[java.sql.Timestamp]("cart_createtime"),
        item.getAs[String]("dt"), item.getAs[String]("dn"), randInt + "_" + courseid)
    })
})

// 小表进行扩容，扩大10倍
val newSaleCourse = saleCourse.flatMap(item => {
    val list = new ArrayBuffer[DwdSaleCourse]()

    val courseid = item.getAs[Int]("courseid")
    val coursename = item.getAs[String]("coursename")
    val status = item.getAs[String]("status")
    val pointlistid = item.getAs[Int]("pointlistid")
    val majorid = item.getAs[Int]("majorid")
    val chapterid = item.getAs[Int]("chapterid")
    val chaptername = item.getAs[String]("chaptername")
    val edusubjectid = item.getAs[Int]("edusubjectid")
    val edusubjectname = item.getAs[String]("edusubjectname")
    val teacherid = item.getAs[Int]("teacherid")
    val teachername = item.getAs[String]("teachername")
    val coursemanager = item.getAs[String]("coursemanager")
    val money = item.getAs[java.math.BigDecimal]("money")
    val dt = item.getAs[String]("dt")
    val dn = item.getAs[String]("dn")

    for (i <- 0 until 10) {
        list.append( DwdSaleCourse(courseid, coursename, status, pointlistid, majorid, chapterid, 
            chaptername, edusubjectid, edusubjectname, teacherid, teachername, coursemanager, money, dt, dn, courseid + "_" + i) )
    }
    list
})

// 两张新表进行join
newSaleCourse.join( newCourseShoppingCart.drop("courseid").drop("coursename"), Seq("rand_courseid", "dt", "dn"), "right" ).drop( "rand_courseid", "dt", "dn" )
```

### 4.3 SMB join

* sort merge bucket操作，适用于大表 join 大表的情况
* 需要进行分桶，首先会进行排序，然后根据key值合并，把相同key的数据放到同一个bucket中（按照key进行hash）
* 实际相当于大表拆分为小表，相同key的数据都在同一个桶中之后，再进行join操作，那么在联合的时候就会大幅度的减小无关项的扫描
* 主要是优化 sort merge join 前的排序时间
* 使用条件：
    1. 两表进行分桶，桶的个数必须相等
    2. 两边进行 join 时，join列 == 排序列 == 分桶列

* 重新生成分桶表

```scala
sparkSession.read.json("/user/atguigu/ods/coursepay.log")
    .write.partitionBy("dt", "dn")
    .format("parquet")
    .bucketBy(5, "orderid")
    .sortBy("orderid")
    .mode(SaveMode.Overwrite)
    .saveAsTable("dwd.dwd_course_pay_cluster")

sparkSession.read.json("/user/atguigu/ods/courseshoppingcart.log")
    .write.partitionBy("dt", "dn")
    .bucketBy(5, "orderid")
    .format("parquet")
    .sortBy("orderid")
    .mode(SaveMode.Overwrite)
    .saveAsTable("dwd.dwd_course_shopping_cart_cluster")
```

* 两张新分桶表join

```scala
val coursePay = sparkSession.sql("select * from dwd.dwd_course_pay_cluster")
  .withColumnRenamed("discount", "pay_discount")
  .withColumnRenamed("createtime", "pay_createtime")
val courseShoppingCart = sparkSession.sql("select *from dwd.dwd_course_shopping_cart_cluster")
  .drop("coursename")
  .withColumnRenamed("discount", "cart_discount")
  .withColumnRenamed("createtime", "cart_createtime")

val tmpdata = courseShoppingCart.join( coursePay, Seq("orderid"), "left" ).drop("orderid")
```

## 5、堆外内存的使用

* 需要缓存大数据量的数据时可考虑使用堆外内存，可减少 JVM 的 GC 压力，加快数据的复制速度
* 代码中使用 persist(StorageLevel.OFF_HEAP) 缓存数据
* 作业提交时开启堆外内存，并配置堆外内存大小

```bash
spark-submit \
--master yarn \
--deploy-mode client \
--driver-memory 1g \
--num-executors 3 \
--executor-cores 4 \
--executor-memory 4g \
--conf spark.driver.memoryOverhead=1g \
--conf spark.memory.offHeap.enabled=true \
--conf spark.memory.offHeap.size=1g  \
--queue spark \
--class com.atguigu.sparksqltuning.OFFHeapCache \
spark-sql-tuning-1.0-SNAPSHOT-jar-with-dependencies.jar
```

## 6、Spark 3.0 AQE

### 6.1 Dynamically coalescing shuffle partitions

* 动态调整 shuffle 分区数，即 task 数

### 6.2 Dynamically switching join strategies

* 动态切换 join 类型，可在运行时根据实际数据大小自动转换为 broadcast hash join

### 6.3 Dynamically optimizing skew joins

* 动态启用 skew join，会将倾斜的分区拆分为 2 个小分区分别进行 join
