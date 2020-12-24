#!/bin/bash

# 脚本作用：将pg库表中数据导出到hive库对应的表中
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

inc_end=$(getparam inc_end)

pg_connection=$(getparam jdbc_str)
username=$(getparam db_user)
password=$(getparam db_psw)

hdp_user_name=$(getparam hdp_user_name)
hsfs_host=$(getparam hsfs_host)
queue_name=$(getparam hdp_queue)
db_name_hive=$(getparam hive_db_name)

table_name=$(getparam task_instance_name)
split_id=$(getparam split_id)
map_num=$(getparam map_num)

data_dt=$(date -d "${inc_end} -3 days" +"%Y-%m-%d")
echo "${data_dt}"

echo "==========导入数据=========="

# 获取hive中间表字段
col=$(hive -e "desc ${db_name_hive}.original_${table_name}" | sed '1d' | sed '/^\s*$/,$d' | awk '{printf $1","}' | sed 's/,$/\n/g')

# 导入数据到hive中间表
do_ex "sqoop import -D mapred.job.queue.name=${queue_name} \
    --connect ${pg_connection} \
    --username ${username} \
    --password ${password} \
    --query 'select ${col} from ${table_name} where 1=1 and \$CONDITIONS' \
    --hive-database ${db_name_hive} \
    --hive-table original_${table_name} \
    --hive-import \
    --hive-overwrite \
    ${col} \
    --delete-target-dir \
    --target-dir /apps-data/${hdp_user_name}/${db_name_hive}/original_${table_name} \
    --fetch-size 2000 \
    --fields-terminated-by '\001' \
    --lines-terminated-by '\n' \
    --columns ${col} \
    --input-null-string '\\\\N' \
    --input-null-non-string '\\\\N' \
    --hive-drop-import-delims \
    -m ${map_num} \
    --split-by ${split_id}"

# 中间表数据导入正式表分区
hive -v -e "
use ${db_name_hive};
set mapred.job.queue.name=${queue_name};
set hive.exec.dynamic.partition=true;
set hive.exec.dynamic.partition.mode=nonstrict;
set hive.exec.max.dynamic.partitions.pernode=1000;

insert overwrite table ${table_name} partition(data_dt)
select ${col}, valuationdate from original_${table_name};
"

echo "==========检验数据=========="

hive_data_num=$(hadoop fs -cat "${hsfs_host}user/hive/warehouse/${db_name_hive}.db/original_${table_name}/*" | wc -l)

sqoop_eval="sqoop_eval --connect ${pg_connection} --username ${username} --password ${password} --query"
pg_data=$(${sqoop_eval} "select count(*) from ${table_name}")
pg_data_num=$(echo "${pg_data}" | awk -F'|' '{print $4}' | tr -d " ")

if [[ ${hive_data_num} == "${pg_data_num}" ]]; then
    echo "\033[5;31;1m SUCCESSFUL:\033[0m ${table_name} 在hive中数据量为 ${hive_data_num} ，导出到pg库的数据量为 ${pg_data_num} ，数据量一致！"
    exit 0
else
    echo "\033[5;31;1m SUCCESSFUL:\033[0m ${table_name} 在hive中数据量为 ${hive_data_num} ，导出到pg库的数据量为 ${pg_data_num} ，数据量不一致，请查明原因！"
    exit 1
fi
