#!/bin/bash

#################################################################################
# 功能描述：从数据湖导出hive表到kylin集群
# 执行示例：./hadoop_distcp_kylin_cluster.sh -param=xxxxxx
#################################################################################

source ExitCodeCheck.sh

opts=$*

# 函数：解析参数
getparam() {
  arg=$1
  echo "${opts}" | xargs -n1 | cut -b 2- | awk -F'=' '{if($1=="'"${arg}"'") print $2}'
}

# 函数：同步hive表
datalake2kyliln() {
  database=$1
  queue_name=$2
  tables=$3
  nn1_host=$4
  nn2_host=$5

  # 1、输出全部表名
  echo "---------------Tables---------------"
  for table in "${tables[@]}"; do
    echo "${database}.${table}"
  done
  echo "---------------Tables---------------"

  # 2、同步hive表数据
  for table in "${tables[@]}"; do
    echo "--------------------------------------------"
    echo "Exporting table ${database}.${table}"
    echo "--------------------------------------------"

    hadoop distcp \
      -Dmapreduce.job.queuqname="${queue_name}" \
      -Dmapreduce.job.name="data_export_${database}_${table}" \
      -update -append -delete -prbug \
      "/user/hive/warehouse/${database}.db/${table}" \
      "hdfs://${nn1_host}:9000/user/hive/warehouse/${database}.db/${table}"

    if [[ ! $? == 0 ]]; then
      hadoop distcp \
        -Dmapreduce.job.queuqname="${queue_name}" \
        -Dmapreduce.job.name="data_export_${database}_${table}" \
        -update -append -delete -prbug \
        "/user/hive/warehouse/${database}.db/${table}" \
        "hdfs://${nn2_host}:9000/user/hive/warehouse/${database}.db/${table}"
    fi

    exitCodeCheck $?
    echo "--------------------------------------------"
    echo "Exporting table ${database}.${table} success"
    echo "--------------------------------------------"
  done
}

# 1、获取传入的参数
database=$(getparam hive_db_name)
queue_name=$(getparam hdp_queue)
hdfs_host=$(getparam hdfs_host)
instance_name=$(getparam task_instance_name) # 传入多个表名用“,”做分隔符

# tables=(${instance_name//,/ })
IFS=" " read -r -a tables <<< "${instance_name//,/ }"

# 2、判断环境，测试、生产
if [[ "${hdfs_host}" =~ "-stg" ]]; then
    stg-prd=stg
    nn1_host=
    nn2_host=
else
    stg-prd=prd
    nn1_host=
    nn2_host=
fi
echo "stg-prd: ${stg-prd}"
echo "nn1_host: ${nn1_host}"
echo "nn2_host: ${nn2_host}"

# 3、数据同步
echo "---------------Export data---------------"
datalake2kyliln "${database}" "${queue_name}" "${tables[@]}" "${nn1_host}" "${nn2_host}"
echo "---------------Export data---------------"

exitCodeCheck $?
