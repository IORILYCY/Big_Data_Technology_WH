#!/bin/bash

# 脚本作用：将hive表中数据导出到pg库对应的表中
# 传参示例：-jdbc_str=jdbc:postgresql://host:port/db_name

opts=$*

function getparam() {
    arg=$1
    echo "${opts}" | xargs -n1 | cut -b 2- | awk -F'=' '{if($1 == "'"${arg}"'") print $2}'
}

function do_ex() {
    eval "$1" || {
                 echo "\033[5;31;1m exec failed:\033[0m 请检查参数是否正确并重新执行！"
                                                                                                        exit 1
  }
}

pg_connection=$(getparam jdbc_str)
username=$(getparam db_user)
password=$(getparam db_psw)
db_name_hive=$(getparam hive_db_name)
table_name=$(getparam task_instance_name)
queue_name=$(getparam hdp_queue)
map_num=$(getparam map_num)

echo "==========导出数据=========="

hadoop fs -test -e "/user/hive/warehouse/${db_name_hive}.db/${table_name}"

if [[ $? -eq 0 ]]; then

    #清空pg库目标表
    sqoop_eval="sqoop_eval --connect ${pg_connection} --username ${username} --password ${password} --query"
    do_ex "${sqoop_eval} \"truncate table ${table_name}\""

    #获取hive表字段
    col=$(hive -e "desc ${db_name_hive}.${table_name}" | sed '1d' | sed '/^\s*$/,$d' | awk '{printf $1","}' | sed 's/,$/\n/g')

    #导出数据
    do_ex "sqoop export -D mapred.job.queue=${queue_name} \
        --connect ${pg_connection} \
        --username ${username} \
        --password ${password} \
        --table ${table_name} \
        --export-dir /user/hive/warehouse/${db_name_hive}.db/${table_name} \
        --columns ${col} \
        --input-null-string '\\\\N' \
        --input-null-non-string '\\\\N' \
        --input-fields-terminated-by '\033' \
        -m ${map_num}"

    echo "==========检验数据=========="

    hive_data_num=$(hadoop fs -cat "/user/hive/warehouse/${db_name_hive}.db/${table_name}/*" | wc -l)
    pg_data=$(${sqoop_eval} "select count(*) from ${table_name}")
    pg_data_num=$(echo "${pg_data}" | awk -F'|' '{print $4}' | tr -d " ")

    if [[ ${hive_data_num} == "${pg_data_num}" ]]; then
        echo "\033[5;31;1m SUCCESSFUL:\033[0m ${table_name} 在hive中数据量为 ${hive_data_num} ，导出到pg库的数据量为 ${pg_data_num} ，数据量一致！"
        exit 0
  else
        echo "\033[5;31;1m ERROR:\033[0m ${table_name} 在hive中数据量为 ${hive_data_num} ，导出到pg库的数据量为 ${pg_data_num} ，数据量不一致，请查明原因！"
        exit 1
  fi

else
    echo "hive数据文件不存在，请进行确认！"
    exit 0
fi
