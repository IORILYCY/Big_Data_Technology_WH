# Yarn-Cluster 模式任务流程

## 一、任务提交流程

1. 执行脚本提交任务，实际是启动一个 SparkSubmit 的 `JVM 进程`

2. `SparkSubmit` 类中的 main 方法 `反射调用` `YarnClusterApplication` 的 main 方法创建客户端

3. `YarnClusterApplication` 在客户端创建 yarnClient，向 `ResourceManager` 提交用户的应用程序

4. RM 发送执行指令：`bin/java ApplicationMaster`，在指定的 `NodeManager` 中启动 `ApplicationMaster 进程`

5. `ApplicationMaster` 启动 `Driver 线程`，执行用户的作业

6. AM 创建 `RMClient` 向 RM 注册，申请资源

7. RM 返回资源列表后 AM 创建 `NMClient` 向 NM 发送指令：`bin/java YarnCoarseGrainedExecutorBackend`

8. `CoarseGrainedExecutorBackend 进程` 会接收消息，跟 Driver 通信，注册已经启动的 Executor 然后 启动 `计算对象 Executor` 等待接收任务

9. `Driver 线程` 继续执行完成作业的调度和任务的执行

10. Driver 分配任务并监控任务的执行

* 注意：
  * `SparkSubmit`、`ApplicationMaster` 和 `CoarseGrainedExecutorBackend` 是独立的`进程`
  * `Driver` 是独立的`线程`
  * `Executor` 和 `YarnClusterApplication` 是`对象`

----

## 二、任务调度原理

* 一个 Spark 应用程序包含的几个概念：
    1. `Job` 是以 Action 算子为界，遇到一个 Action 算子则触发一个 Job
    2. `Stage` 是 Job 的子集，以 RDD宽依赖（即 Shuffle）为界，遇到 Shuffle 做一次划分
    3. `Task` 是 Stage 的子集，以并行度（partition 数）来衡量，分区数是多少，就有多少个 task
* 执行过程中涉及到两个调度器
  * `DAGScheduler` 负责 Stage级 的调度，主要是将 job 切分成若干 Stages，并将每个 Stage 打包成 TaskSet 交给 `TaskScheduler` 调度
  * `TaskScheduler` 负责 Task级 的调度，将 `DAGScheduler` 给过来的 TaskSet 按照指定的调度策略分发到 Executor 上执行，调度过程中 `SchedulerBackend` 负责提供可用资源，其中 `SchedulerBackend` 有多种实现，分别对接不同的资源管理系统
* Driver 初始化 SparkContext 过程中会分别初始化 DAGScheduler、TaskScheduler、SchedulerBackend、HeartbeatReceiver，并启动 SchedulerBackend、HeartbeatReceiver。`SchedulerBackend` 负责通过 AM 申请资源和与 Executor 通信，`HeartbeatReceiver` 负责接收 Executor 的心跳信息，并通知 `TaskScheduler` Executor 的存货状态

### 1、Stage 级调度

* Spark 的任务调度是从 DAG 切割开始，主要是由 `DAGScheduler` 来完成
* 一个 Job 由最终的 RDD 和 Action 算子封装组成
  
1. SparkContext 将 Job 交给 `DAGScheduler` 提交后，`DAGScheduler` 会按血缘关系不断回溯最终 RDD 的父 RDD，每遇到一个宽依赖（shuffle）执行一次 Stage 划分，宽依赖间的窄依赖都会被划分到同一个 Stage ，进行 pipeline 式的计算
2. 最终的 Stage 称为 `ResultStage`，这之前的所有 Stage 都是为下一个 Stage 准备数据的，全部称为 `ShuffleMapStage`
3. Stages 划分结束后会开始进行提交，Stage 的提交会不断追溯他的父 Stage ，只有在父 Stage 执行完毕后，才会提交子 Stage
    * Stage的提交过程会将 Task 信息（partition 及方法等）序列化并打包成 `TaskSet` 发送给 `TaskScheduler`，一个 Partition 对应一个 Task
    * `TaskSet` 是一个 Stage 中包含的所有 Task 的集合
4. `TaskScheduler` 会监控每一个 Stage 的运行状态，只有 Executor 丢失或者 Task 由于 Fetch 失败才需要重新提交 Stage 调度运行失败的任务，其他类型的 Task 失败会在 TaskScheduler 的调度过程中重试

### 2、Task 级调度

1. `TaskScheduler` 接收到 TaskSet 后，会将其封装为 `TaskSetManager` 并放入调度池等待执行，`TaskSetManager` 用于负责监控管理同一个 Stage 中的所有 Task，`TaskScheduler` 以 `TaskSetManager` 为单元进行调度任务
2. `TaskScheduler` 初始化后会启动 `SchedulerBackend`，由 `SchedulerBackend` 接收 Executor 的注册信息，并维护 Executor 的状态，筛选活跃 Executor，定期向 `TaskScheduler` 询问是否有需要执行的任务，而 `TaskScheduler` 则会按指定的`调度策略`从调度池中选择需要执行的 `TaskSetManager` 调度运行

   * 调度策略：
    1. FIFO（默认策略）：将 `TaskSetManager` 按先进先出的原则保存到调度池中的一个调度队列
    2. FAIR：包含一个 `rootPool` 和多个 子`Pool`，调度时需要先对 子`Pool` 进行排序，再对其中的 `TaskSetManager` 排序，排序结束后，所有的 `TaskSetManager` 会放入一个 ArrayBuffer 中，然后按顺序取出调度运行。排序原则为：
        * 二者排序采用相同的算法，需要对每个排序对象的 `runningTasks、minShare、weight` 三个属性进行比较
        * runningTasks 比 minShare 小的先执行
        * 若 runningTasks 都比 minShare 小，则 minShare使用率（runningTasks/minShare）低的先执行
        * 若 runningTasks 都比 minShare 大，则权重使用率（runningTasks/weight）低的先执行
        * 若上述比较均相等，则比较名字

3. `TaskSetManager` 被取出后，由 `TaskSetManager` 取出其中的一个个 Task 发送给 `TaskScheduler`，再交由 `SchedulerBackend` 将 Task 发送给 Executor 执行

* 本地化调度：
  * `TaskSetManager` 根据 Task 的优先位置确定其 Locality级别，以 Task 的最高 Locality级别 来确定将它发送到哪个 Executor 执行，本地化级别按高低排序依次为（级别越高性能越好）：

    |名称|备注|
    |:- |:- |
    |PROCESS_LOCAL（进程本地化）|task和数据在同一个Executor中|
    |NODE_LOCAL（节点本地化）|task和数据在同一个节点中|
    |RACK_LOCAL（机架本地化）|task和数据在同一个机架的两个节点中|
    |NO_PREF|task从哪里获取数据都一样，没有好坏之分|
    |ANY|task和数据可以在集群中的任意节点上，且不在同一机架上|

### 3、失败重试机制

1. Executor 将 Task 的执行状态上报给 `SchedulerBackend`
2. `SchedulerBackend` 通知 `TaskScheduler`
3. `TaskScheduler` 确定 Task 属于哪个 `TaskSetManager`，并通知它 Task 执行状态
4. 对于失败的 Task，`TaskSetManager` 会记录其失败次数，若没有超过最大重试次数，则将其放回调度池等待重新调度，反之整个 Spark程序 失败

* 对于失败的 Task，会启用黑名单机制，黑名单中记录它上次失败所在的 Executor ID、Host 以及拉黑时间，下次调度时不再将其发送到失败过的节点

## 三、参数优化

```bash
bin/spark-submit \
--class com.xyz.bigdata.calendar.PeriodCalculator \
--master yarn \
--deploy-mode cluster \
--queue default_queue \
--num-executors 50 \
--executor-cores 2 \
--executor-memory 4G \
--driver-memory 2G \
--conf "spark.default.parallelism=250" \
--conf "spark.shuffle.memoryFraction=0.3" \
--conf "spark.storage.memoryFraction=0.5" \
--conf "spark.driver.extraJavaOptions=-XX:+UseG1GC" \
--conf "spark.executor.extraJavaOptions=-XX:+UseG1GC" \
--verbose \
${PROJECT_DIR}/bigdata-xyz-0.1.jar
```

* num-executors
  * 含义：设定Spark作业要用多少个Executor进程来执行
  * 设定方法：根据我们的实践，设定在30~100个之间为最佳。如果不设定，默认只会启动非常少的Executor。如果设得太小，无法充分利用计算资源。设得太大的话，又会抢占集群或队列的资源，导致其他作业无法顺利执行

* executor-cores
  * 含义：设定每个Executor能够利用的CPU核心数（这里核心指的是vCore）。核心数越多，并行执行Task的效率也就越高
  * 设定方法：根据我们的实践，设定在2~6之间都是可以的，主要是根据业务类型和数据处理逻辑的复杂程度来定，一般来讲设2或者3就够用了。需要注意的是，num-executors * executor-cores不能将队列中的CPU资源耗尽，最好不要超过总vCore数的1/3，以给其他作业留下剩余资源

* executor-memory
  * 含义：设定每个Executor的内存量（堆内内存）。这个参数比executor-cores更为重要，因为Spark作业的本质就是内存计算，内存的大小直接影响性能，并且与磁盘溢写、OOM等都相关
  * 设定方法：一般设定在2G~8G之间，需要根据数据量慎重做决定。如果作业执行非常慢，出现频繁GC或者OOM，就得适当调大内存。并且与上面相同，num-executors * executor-memory也不能过大，最好不要超过队列总内存量的一半
  * 另外，还有一个配置项spark.executor.memoryOverhead，用来设定每个Executor可使用的堆外内存大小，默认值是executor-memory的0.1倍，最小值384M。一般来讲都够用，不用特意设置

* driver-memory
  * 含义：设定Driver进程的内存量（堆内内存）
  * 设定方法：由于我们几乎不会使用collect()之类的算子把大量RDD数据都拉到Driver上来处理，所以它的内存可以不用设得过大，2G可以应付绝大多数情况。但是，如果Spark作业处理完后数据膨胀比较多，那么还是应该酌情加大这个值
  * 与上面一项相同，spark.driver.memoryOverhead用来设定Driver可使用的堆外内存大小

* spark.default.parallelism
  * 含义：对于shuffle算子，如reduceByKey()或者join()，这个参数用来指定父RDD中最大分区数。由于分区与Task有一一对应关系，因此也可以理解为Task数。其名称的字面意义是“并行度”，不能直接表达出这种含义
  * 设定方法：Spark官方文档中推荐每个CPU core执行2~3个Task比较合适，因此这个值要设定为(num-executors * executor-cores)的2~3倍。这个参数同样非常重要，因为如果不设定的话，分区数就会由RDD本身的分区来决定，这样往往会使得计算效率低下

* spark.shuffle.memoryFraction
  * 含义：shuffle操作（聚合、连接、分组等等）能够使用的可用堆内存（堆大小减去300MB保留空间）的比例，默认值是0.2。如果shuffle阶段使用的内存比例超过这个值，就会溢写到磁盘
  * 设定方法：取决于计算逻辑中shuffle逻辑的复杂度，如果会产生大量数据，那么一定要调高。在我们的实践中，一般都设定在0.3左右。但是，如果调太高之后发现频繁GC，那么就是执行用户代码的execution内存不够用了，适当降低即可

* spark.storage.memoryFraction
  * 含义：缓存操作（persist/cache）能够使用的可用堆内存的比例，默认值是0.6
  * 设定方法：如果经常需要缓存非常大的RDD，那么就需要调高。否则，如果shuffle操作更为重量级，适当调低也无妨。我们一般设定在0.5左右
  * 其实，spark.shuffle/storage.memoryFraction是旧版的静态内存管理（StaticMemoryManager）的遗产。在Spark 1.6版本之后的文档中已经标记成了deprecated。目前取代它们的是spark.memory.fraction和spark.memory.storageFraction这两项，参考新的统一内存管理（UnifiedMemoryManager）机制可以得到更多细节
  * 前者的含义是总内存占堆的比例，即execution+storage+shuffle内存的总量。后者则是storage内存占前者的比例。默认值分别为0.75（最新版变成了0.6）和0.5

* spark.driver/executor.extraJavaOptions
  * 含义：Driver或Executor进程的其他JVM参数
  * 设定方法：一般可以不设置。如果设置，常见的情景是使用-Xmn加大年轻代内存的大小，或者手动指定垃圾收集器（最上面的例子中使用了G1，也有用CMS的时候）及其相关参数
