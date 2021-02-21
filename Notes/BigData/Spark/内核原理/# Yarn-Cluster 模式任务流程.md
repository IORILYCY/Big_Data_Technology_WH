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
