# Hive优化

## 1、SQL语法优化

### 1.1 count(distinct)

* 使用 `SIZE(COLLECT_SET( col ))` 代替 `COUNT(DISTINCT ol)`
* 使用 `group by` 去重后再做 `count` 操作

### 1.2 order by

* 全局排序，只启用1个reducer，性能低下，即使配置reducer数也不起作用

#### 1.2.1 有limit限制的topN问题

* 使用窗口函数排序取前n的数据做子查询（按具体需求选择排序函数），再使用 `order by` 获取全局排序结果
  * `rank`：排名相同的取相同值，后续排名`会`跳过重复的数量
  * `dense_rank`：排名相同的取相同值，后续排名`不会`跳过重复的数量
  * `row_number`：行号，不管排序字段是否有重复，都按1,2,3,4,……,n排序

#### 1.2.2 没有limit限制的全局排序问题

* 分组内有序的需求下可使用 `distribute by 分组字段 sort by 排序字段` 代替 `order by`
* 全局有序时，正序可使用 `cluster by`，逆序可使用 `distribute by 排序字段 sort by 排序字段 desc`
* 使用时需要设置reducer数：`set mapreduce.job.reduces=[n];`
