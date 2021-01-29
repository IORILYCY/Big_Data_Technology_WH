#!/bin/bash

#################################################################################
# 功能描述：Kylin删除Mode和Cube
# 执行示例：./kylin_cube_delete.sh -param=xxxxxx
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

# 1、获取传入的参数
user=$(getparam user)
passwd=$(getparam passwd)
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

# 4、删除Cube
cubes=()

for cube in "${cubes[@]}"; do
  echo "Delete the cube: ${cube}"

  disable=$(curl -X PUT \
    -H "Authorization: Basic ${usr}" \
    -H 'Content-Type: application/json;charset=UTF-8' \
    "http://${kylin_host1}:${port}/kylin/api/cubes/${cube}/disable")

  disable_id=$(echo "${disable}" | awk -F',' '{print $1}' | awk -F':' '{print $2}' | sed 's/\"//g')

  if [[ ${disable_id} == 999 ]]; then
      echo "Failed disable the cube: ${cube}, please check log!"
      echo "${disable}"
      echo ""
  else
        echo "Succeed disable the cube: ${cube}!"
        echo "disable_id: ${disable_id}"
        echo ""
  fi

  purge=$(curl -X PUT \
    -H "Authorization: Basic ${usr}" \
    -H 'Content-Type: application/json;charset=UTF-8' \
    "http://${kylin_host1}:${port}/kylin/api/cubes/${cube}/purge")

  purge_id=$(echo "${purge}" | awk -F',' '{print $1}' | awk -F':' '{print $2}' | sed 's/\"//g')

  if [[ ${purge_id} == 999 ]]; then
      echo "Failed purge the cube: ${cube}, please check log!"
      echo "${purge}"
      echo ""
  else
        echo "Succeed purge the cube: ${cube}!"
        echo "purge_id: ${purge_id}"
        echo ""
  fi

  drop_cube=$(curl -X DELETE \
    -H "Authorization: Basic ${usr}" \
    -H 'Content-Type: application/json;charset=UTF-8' \
    "http://${kylin_host1}:${port}/kylin/api/cubes/${cube}")

  drop_cube_id=$(echo "${drop_cube}" | awk -F',' '{print $1}' | awk -F':' '{print $2}' | sed 's/\"//g')

  if [[ ${drop_cube_id} == 999 ]]; then
      echo "Failed drop the cube: ${cube}, please check log!"
      echo "${drop_cube}"
      echo ""
  else
        echo "Succeed drop the cube: ${cube}!"
        echo "drop_cube_id: ${drop_cube_id}"
        echo ""
  fi
done

# 5、删除Model
models=()

for model in "${models[@]}"; do
  echo "Delete the model: ${model}"

  drop_model=$(curl -X DELETE \
    -H "Authorization: Basic ${usr}" \
    -H 'Content-Type: application/json;charset=UTF-8' \
    "http://${kylin_host1}:${port}/kylin/api/models/${model}")

  drop_model_id=$(echo "${drop_model}" | awk -F',' '{print $1}' | awk -F':' '{print $2}' | sed 's/\"//g')

  if [[ ${drop_model_id} == 999 ]]; then
      echo "Failed drop the model: ${model}, please check log!"
      echo "${drop_model}"
      echo ""
  else
        echo "Succeed drop the model: ${model}!"
        echo "drop_cubdrop_model_ide_id: ${drop_model_id}"
        echo ""
  fi
done

# 6、刷新元数据
meta_sync "${kylin_host1}" "${kylin_host2}" "${kylin_host3}" "${usr}" "${project}"

exitCodeCheck $?
