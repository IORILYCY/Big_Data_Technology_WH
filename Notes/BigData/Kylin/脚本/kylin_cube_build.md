# kylin_cube_build.sh
```bash
#################################################################################
# 功能描述：Kylin构建Cube
# 执行示例：./kylin_cube_build.sh -param=xxxxxx
#################################################################################

#!/bin/bash
opts=$@

getparam(){
	arg=$1
	echo ${opts} |xargs -n1 |cut -b 2- |awk -F'=' '{if($1=="'${arg}'") print $2}'
}

# 1、获取传入的参数
user=$(getparam user)
passwd=$(getparam passwd)
cube_name=$(getparam cube_name)
today=$(date +%F)
ebd_date=$(getparam ebd_date)
mode=$(getparam mode)
kylin_env=$(getparam kylin_env)

# 2、获取用户验证密文
if [ ! -n "${user}" -a ! -n "${passwd}" ]; then
	echo "User is ADMIN"
	user="ADMIN"
	usr=""
elif [ -n "${user}" -a -n "${passwd}" ]; then
	echo "User is ${user}"
	usr=$(python -c "import base64; print base64.standard_b64encode('${user}:${passwd}')")
else
	echo "请配置正确的用户及密码!"
fi

# 3、获取Cube结束时间
if [ ! -n "${end_date}" ]; then
	# 未传参则为当天00:00:00
	end=$[$(date -d "${today} 08:00:00" +%s) * 1000]
else
	# 传参则为参数那天的00:00:00
	end=$[$(date -d "${end_date} 08:00:00" +%s) * 1000]
fi

# 4、判断环境，测试、生产，通过参数kylin_env，如果kylin_env=kylin-stg
if [[ "${kylin_env}" =~ "-stg" ]];then
    stg-prd=stg
    kylin_host=
else
    stg-prd=prd
    kylin_host=
fi
echo "stg-prd: ${stg-prd}"
echo "kylin_host: ${kylin_host}"

# 5、构建Cube
# 5.1、初始构建
if [ ${mode} == 'build' ]; then
	# 输出Cube信息
	echo "***************Rebuild Cube***************"
	echo "Cube       ${cube_name}"
	echo "User       ${user}"
	echo "Mode       ${mode}"

	# 构建Cube
	curl -X PUT \
	-H "Authorization: Basic ${usr}" \
	-H "Connect-Type: application/json" \
	-d '{"buildType":"BUILD"}' \
	http://${kylin_host}:port/kylin/api/cubes/${cube_name}/build

# 5.2、增量构建
elif [ ${mode} == 'rebuild' ]; then
	# 输出Cube信息
	echo "***************Rebuild Cube***************"
	echo "Cube       ${cube_name}"
	echo "User       ${user}"
	echo "Mode       ${mode}"
	echo "EndTime    $(date -d @$[${end} / 1000 - 28800] "+%Y-%m-%d %H:%M:%S")"

	# 构建Cube
	curl -X PUT \
	-H "Authorization: Basic ${usr}" \
	-H "Connect-Type: application/json" \
	-d '{"endTime":'${end}', "buildType":"BUILD"}' \
	http://${kylin_host}:port/kylin/api/cubes/${cube_name}/rebuild

# 5.3、全量刷新
elif [ ${mode} == 'refresh' ]; then
	# 输出Cube信息
	echo "***************Refresh Cube***************"
	echo "Cube       ${cube_name}"
	echo "User       ${user}"
	echo "Mode       ${mode}"
	echo "***************Refresh Cube***************"

	# 构建Cube
	curl -X PUT \
	-H "Authorization: Basic ${usr}" \
	-H "Connect-Type: application/json" \
	-d '{"buildType":"REFRESH"}' \
	http://${kylin_host}:port/kylin/api/cubes/${cube_name}/build

else
	echo "请配置正确的构建模式! ( build / rebuild / refresh )"
fi
```