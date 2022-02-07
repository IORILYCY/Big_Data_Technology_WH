#!/bin/bash

#################################################################################
# 功能描述：Kylin新建Mode和Cube
# 执行示例：./kylin_cube_create.sh -param=xxxxxx
#################################################################################

source ExitCodeCheck.sh

opts=$*

# 函数：解析参数
getparam() {
  arg=$1
  echo "${opts}" | xargs -n1 | cut -b 2- | awk -F'=' '{if($1=="'"${arg}"'") print $2}'
}

# 函数：kylin集群同步元数据
meta_sync() {
  kylin_host1=$1
  kylin_host2=$2
  kylin_host3=$3
  usr=$4
  project=$5

  echo "sync_time: $(date)"

  for kylin_host in kylin_host1 kylin_host2 kylin_host3; do
    echo "Metadata sync: ${kylin_host}"
    curl -X PUT \
      -H "Authorization: Basic ${usr}" \
      -H 'Content-Type: application/json;charset=UTF-8' \
      "http://${kylin_host}:7070/kylin/api/cache/project/${project}/update"
  done

  sleep 3
}

# 函数：创建Model或Cube
create() {
  type=$1
  kylin_host=$2
  port=$3
  usr=$4
  project=$5
  desc_file=$6

  for desc_data in $(cat "${desc_file}"); do
    name=$(echo "${desc_data}" | sed 's/\\//g' | python -c "import sys, json; desc=json.load(sys.stdin); print desc['name']")
    echo "Create ${type}: ${name}"
    desc="{\"${type}Name\":\"\", \"project\":\"${project}\", \"${type}DescData\":\"${desc_data}\"}"

    create=$(
             curl -X POST \
        -H "Authorization: Basic ${usr}" \
        -H 'Content-Type: application/json;charset=UTF-8' \
        -d "${desc}"
      "http://${kylin_host}:${port}/kylin/api/${type}s"
    )

    id=$(echo "${create}" | awk -F',' '{print $1}' | awk -F':' '{print $2}' | sed 's/\"//g')

    if [[ ${id} == 999 ]]; then
      echo "Failed create ${type}: ${name}, please check log!"
      echo "${create}"
      echo ""

    else
      echo "Succeed create ${type}: ${name}!"
      echo "${type}_id: ${id}"
      echo ""
    fi
  done
}

# 1、获取传入的参数
user=$(getparam user)
passwd=$(getparam passwd)
project_nm=$(get project)
hdfs_host=$(getparam hdfs_host)

# 2、获取用户验证密文
if [[ -z "${user}" ]] && [[ -z "${passwd}" ]]; then
  echo "User is [ADMIN]"
  user="ADMIN"
  usr="QURNSU46S1lMSU4="
elif [[ -n "${user}" ]] && [[ -n "${passwd}" ]]; then
  echo "User is [${user}]"
  usr=$(python -c "import base64; print base64.standard_b64encode('${user}:${passwd}')")
else
  echo "请配置正确的用户及密码!"
fi

# 3、判断环境，测试、生产
if [[ "${hdfs_host}" =~ "-stg" ]]; then
    stg-prd=stg
    kylin_host1=
    kylin_host2=
    kylin_host3=
    port=
else
    stg-prd=prd
    kylin_host1=
    kylin_host2=
    kylin_host3=
    port=
fi
echo "stg-prd: ${stg-prd}"
echo "kylin_host1: ${kylin_host1}"
echo "kylin_port: ${port}"

# 4、创建Model
create "model" "${kylin_host1}" "${port}" "${usr}" "${project_nm}" "models_desc"

# 5、创建Cube
create "cube" "${kylin_host1}" "${port}" "${usr}" "${project_nm}" "cubes_desc"

# 6、刷新元数据
meta_sync "${kylin_host1}" "${kylin_host2}" "${kylin_host3}" "${usr}" "${project}"

exitCodeCheck $?
