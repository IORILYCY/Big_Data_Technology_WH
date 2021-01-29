#!/bin/bash

#################################################################################
# 功能描述：Kylin构建Cube
# 执行示例：./kylin_cube_build.sh -param=xxxxxx
#################################################################################

export PYTHONIOENCODING=utf8
source ExitCodeCheck.sh

opts=$*

# 函数：解析参数
getparam() {
  arg=$1
  echo "${opts}" | xargs -n1 | cut -b 2- | awk -F'=' '{if($1=="'"${arg}"'") print $2}'
}

# 函数：kylin集群同步元数据
meta_sync() {
  kylin_host2=$1
  kylin_host3=$2
  kylin_host4=$3
  usr=$4

  echo "sync_time: $(date)"

  for kylin_host in kylin_host2 kylin_host3 kylin_host4; do
    echo "Metadata sync: ${kylin_host}"
    curl -X PUT \
      -H "Authorization: Basic ${usr}" \
      -H 'Content-Type: application/json;charset=UTF-8' \
      "http://${kylin_host}:7070/kylin/api/cache/announce/all/update"
  done

  sleep 3
}

# 函数：重新下发build任务
job_restart() {

  kylin_host1=$1
  port=$2
  usr=$3
  kylin_host2=$4
  kylin_host3=$5
  kylin_host4=$6
  end=$7
  cube_name=$8
  restart=$9

  # 获取job列表
  jobs=$(
         curl -X GET \
      -H "Authorization: Basic ${usr}" \
      -H 'Content-Type: application/json;charset=UTF-8' \
      "http://${kylin_host1}:${port}/kylin/api/jobs"
  )

  len=$(echo "${jobs}" | python -c "import sys, json; print len(json.load(sys.stdin))")

  current_dt=$(date +%F)

  # python判断是否有当前cube的任务
  uuid=$(
         echo "${jobs}" | python -c "
import sys,json,time
jobs=json.load(sys.stdin)
for num in range(0, ${len}):
  if ('BUILD CUBE - ${cube_name}' in jobs[num]['name'] and jobs[num]['job_status']!='FINISHED' and jobs[num]['job_status']!='DISCARDED' and time.strftime('%Y-%m-%d', time.localtime(jobs[num]['exec_start_time']/1000))=='${current_dt}'):
    print(jobs[num]['uuid'])
" | grep -E '\w{8}(-\w{4}){3}-\w{12}'
  )

  echo "uuid: ${uuid}"

  # 若当前存在正在运行的任务，则将uuid赋值给job_id
  if [[ ${uuid} != "" ]]; then
    uuid_len=$(expr length "${uuid}")

    if [[ ${uuid_len} == 36 ]]; then
      job_id=${uuid}
    fi
  # 若当前不存在正在运行的任务，则重新下发
  else
    echo "buiild_time: $(date)"
    job=$(
          curl -X PUT \
        -H "Authorization: Basic ${usr}" \
        -H 'Content-Type: application/json;charset=UTF-8' \
        -d '{"endTime":'"${end}"', "buildType":"BUILD"}' \
        "http://${kylin_host1}:${port}/kylin/api/cubes/${cube_name}/rebuild"
    )

    check_job_status "${job}" "${kylin_host1}" "${port}" "${usr}" "${kylin_host2}" "${kylin_host3}" "${kylin_host4}" "${end}" "${cube_name}" "${restart}"
  fi
}

# 函数：检查build任务状态
check_job_status() {

  # 获取参数
  job=$1
  kylin_host1=$2
  port=$3
  usr=$4
  kylin_host2=$5
  kylin_host3=$6
  kylin_host4=$7
  end=$8
  cube_name=$9
  restart=${10}

  # 获取job_id
  job_id=$(echo "${job}" | awk -F',' '{print $2}' | sed 's/\"//g')
  echo "${job}"
  echo "job_id: ${job_id}"
  echo "kylin_host: ${kylin_host1}"

  # 初始化任务状态
  job_status="PENDING"
  run_time=0
  retry=0

  # 判断任务是否完成
  while [[ ${job_status} != "FINISHED" ]]; do

    # 若任务下发失败，则重新下发
    if [[ ${job_id} == 999 ]] || [[ ${job_id} == "" ]]; then
      run_time=0
      restart=$((restart + 1))
      echo "restart: ${restart}"

      sleep 3

      # 任务下发最大重试设为3次，始终失败则退出脚本
      if [[ ${restart} -lt 3 ]]; then
        # 集群同步元数据
        meta_sync "${kylin_host2}" "${kylin_host3}" "${kylin_host4}" "${usr}"

        # 重新下发任务
        job_restart "${kylin_host1}" "${port}" "${usr}" "${kylin_host2}" "${kylin_host3}" "${kylin_host4}" "${end}" "${cube_name}" "${restart}"
      else
        echo "restart 3 times, the job still ERROR, exit!"
        exit 1
      fi
    # 若任务下发成功，则判断任务执行状态
    else
      # 同步元数据
      meta_sync "${kylin_host2}" "${kylin_host3}" "${kylin_host4}" "${usr}"

      # 获取任务信息
      status=$(
               curl -X GET \
          -H "Authorization: Basic ${usr}" \
          -H 'Content-Type: application/json;charset=UTF-8' \
          "http://${kylin_host1}:${port}/kylin/api/jobs/${job_id}"
      )

      # 获取任务状态
      job_status=$(echo "${status}" | awk -F',' '{print $(NF-2)}' | grep job_status | awk -F':' '{print $2}' | sed 's/\"//g')
      echo "Build segment for ${run_time}s"
      echo "job_status: ${job_status}"

      case ${job_status} in
        "FINISHED")
          # Build成功，同步元数据，退出
          meta_sync "${kylin_host2}" "${kylin_host3}" "${kylin_host4}" "${usr}"
          echo "Build success"
          exit 0
          ;;

        "ERROR")
          # 任务报错，输出错误信息，并重跑任务
          echo "${status}"

          curl -X PUT \
            -H "Authorization: Basic ${usr}" \
            -H 'Content-Type: application/json;charset=UTF-8' \
            "http://${kylin_host1}:${port}/kylin/api/jobs/${job_id}/resume"

          echo "ERROR job resume"
          run_time=0
          retry=$((retry + 1))

          # 任务重试超过3次，则取消本次任务，重新下发
          if [[ ${retry} -gt 3 ]]; then
            echo "Retry 3 times, set job status to 'DISCARDED'"

            curl -X PUT \
              -H "Authorization: Basic ${usr}" \
              -H 'Content-Type: application/json;charset=UTF-8' \
              "http://${kylin_host1}:${port}/kylin/api/jobs/${job_id}/cancel"
            retry=0

            # 同步元数据
            meta_sync "${kylin_host2}" "${kylin_host3}" "${kylin_host4}" "${usr}"

            # 重启新的任务
            echo "Start a new job"
            job=$(
                  curl -X PUT \
                -H "Authorization: Basic ${usr}" \
                -H 'Content-Type: application/json;charset=UTF-8' \
                -d '{"endTime":'"${end}"', "buildType":"BUILD"}' \
                "http://${kylin_host1}:${port}/kylin/api/cubes/${cube_name}/rebuild"
            )

            check_job_status "${job}" "${kylin_host1}" "${port}" "${usr}" "${kylin_host2}" "${kylin_host3}" "${kylin_host4}" "${end}" "${cube_name}" 0
          fi
          ;;

        "STOPPED")
          # 任务被人为停止，将运行时间重置为0等待
          run_time=0
          ;;

        "DISCARDED")
          # 任务被取消，退出
          echo "${status}"
          echo "Job status is set to 'DISCARDED' by someone, exit"
          exit 1
          ;;

        "")
          # 任务节点可能宕机，判断是否退出
          echo "${status}"

          # 通过用户认证验证集群服务情况，若全部节点服务宕机，退出，否则尝试再次获取任务状态
          auth=$(
                 curl -X PUT \
              -H "Authorization: Basic ${usr}" \
              -H 'Content-Type: application/json;charset=UTF-8' \
              -d '{"endTime":'"${end}"', "buildType":"BUILD"}' \
              "http://${kylin_host1}:${port}/kylin/api/user/authentication"
          )
          flag=$(echo "${auth}" | awk -F',' '{print $1}' | awk -F':' '{print $1}' | sed 's/\"//g' | sed 's/{//g')

          if [[ ${flag} == 'userDetails' ]]; then
            echo "Try get job status again"
          else
            echo "Kylin service maybe down, exit"
            exit 1
          fi
          ;;
      esac

      # 任务执行期间，每分钟获取一次任务状态
      sleep 60
      run_time=$((run_time + 60))

      # 单次任务执行超过5小时，则超时，取消任务，退出
      if [[ ${run_time} -gt 18000 ]]; then
        curl -X PUT \
          -H "Authorization: Basic ${usr}" \
          -H 'Content-Type: application/json;charset=UTF-8' \
          "http://${kylin_host1}:${port}/kylin/api/jobs/${job_id}/cancel"

        echo "Time out, set job status to 'DISCARDED'"
        exit 1
      fi
    fi
  done

}

# 1、获取传入的参数
user=$(getparam user)
passwd=$(getparam passwd)

name=$(getparam task_instance_name)
cube_name=$(echo "${name}" | awk -F',' '{print $1}')
echo "cube: ${cube_name}"
table_name=$(echo "${name}" | awk -F',' '{print $2}')
echo "table: ${table_name}"
database=$(getparam hive_db_name)
echo "db: ${database}"

queue=$(getparam hdp_queue)
echo "queue: ${queue}"
hdfs_host=$(getparam hdfs_host)
echo "hdfs: ${hdfs_host}"

inc_start=$(getparam inc_start)
echo "inc_start: ${inc_start}"
inc_end=$(getparam inc_start)
echo "inc_end: ${inc_end}"

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

# 3、获取Cube结束时间
if [[ ${table_name} != "" ]]; then
  mode="rebuild"
  echo "mode: ${mode}"

  max_data_dt=$(hive -e "set hive.cli.print.header=false; set mapred.job.queue.name=${queue}; select max(data_dt) from ${database}.${table_name};")
  max_dt=${max_data_dt[0]:0-8:8}
  echo "max_dt: ${max_dt}"
  end_dt=$(date -d "+1day ${max_dt}" +%Y%m%d)

else
  mode="build"
  echo "mode: ${mode}"

  end_dt=$(date -d "${inc_end}" +%Y%m%d)
fi

end=$(($(date -d "${end_dt} 08:00:00" +%s) * 1000))

# 4、判断环境，测试、生产
if [[ "${hdfs_host}" =~ "-stg" ]]; then
    stg-prd=stg
    kylin_host1=
    kylin_host2=
    kylin_host3=
    kylin_host4=
    port=
else
    stg-prd=prd
    kylin_host1=
    kylin_host2=
    kylin_host3=
    kylin_host4=
    port=
fi
echo "stg-prd: ${stg-prd}"
echo "kylin_host1: ${kylin_host1}"
echo "kylin_port: ${port}"

# 判断构建类型
if [[ ${mode} == "rebuild" ]]; then

  # 同步元数据
  meta_sync "${kylin_host2}" "${kylin_host3}" "${kylin_host4}" "${usr}"

  # 获取cube基本信息
  cube_id=""

  while [[ ${cube_id} == "" ]]; do
    cube=$(
           curl -X GET \
        -H "Authorization: Basic ${usr}" \
        -H 'Content-Type: application/json;charset=UTF-8' \
        "http://${kylin_host1}:${port}/kylin/api/cubes/${cube_name}"
    )

    cube_id=$(echo "${cube}" | awk -F',' '{print $1}' | awk -F':' '{print $2}' | sed 's/\"//g' | grep -E '\w{8}(-\w{4}){3}-\w{12}')
  done

  len=$(echo "${cube}" | python -c "import sys, json; print len(json.load(sys.stdin)['segments'])")
  seg_name=$(echo "{cube}" | python -c "
import sys, json
cube=json.load(sys.stdin)
for num in range(0, ${len}): print(cube['segments'][num]['name'])
" | xargs -d ' ' | grep "_${end_dt}")
  echo "seg_name: ${seg_name}"

  if [[ ${seg_name} != "" ]]; then
    del=$(curl -X DELETE \
      -H "Authorization: Basic ${usr}" \
      -H 'Content-Type: application/json;charset=UTF-8' \
      "http://${kylin_host1}:${port}/kylin/api/cubes/${cube_name}/segs/${seg_name}")

    del_id=$(echo "${del}" | awk -F',' '{print $1}' | awk -F':' '{print $2}' | sed 's/\"//g')

    if [[ ${del_id} == 999 ]]; then
      echo "Failed delete segment, please check log!"
      echo "${del}"
    else
      echo "Succeed delete segment, rebuild the segment!"
      echo "del_id: ${del_id}"
    fi

  else
    echo "Build new segment!"
  fi

elif [[ ${mode} == "build" ]]; then
  echo "Full build cube!"
fi

# 同步元数据
meta_sync "${kylin_host2}" "${kylin_host3}" "${kylin_host4}" "${usr}"

# 输出cube构建信息
echo "***************Build Cube***************"
echo "Cube  ${cube_name}"
echo "User  ${user}"
echo "Mode  ${mode}"
echo "EndTime $(date -d @$((end / 1000 - 28800)) '+%Y-%m-%d %H:%M:%S')"
echo "***************Build Cube***************"

# 下发构建任务
echo "Build start time: $(date)"
job=$(curl -X PUT \
  -H "Authorization: Basic ${usr}" \
  -H 'Content-Type: application/json;charset=UTF-8' \
  -d '{"endTime":'"${end}"', "buildType":"BUILD"}' \
  "http://${kylin_host1}:${port}/kylin/api/cubes/${cube_name}/rebuild")

# 检查任务执行状态
check_job_status "${job}" "${kylin_host1}" "${port}" "${usr}" "${kylin_host2}" "${kylin_host3}" "${kylin_host4}" "${end}" "${cube_name}" 0

exitCodeCheck $?
