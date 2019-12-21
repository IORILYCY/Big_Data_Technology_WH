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

# 2、获取用户验证密文
if [ ! -n "${user}" -a ! -n "${passwd}" ]; then
	echo "User is ADMIN"
	usr=
elif [ -n "${user}" -a -n "${passwd}" ]; then
	echo "User is ${user}"
	usr=$(python -c "import base64; print base64.standard_b64encode('${user}:${passwd}')")
else
	echo "Please set user and password!"
fi

# 3、获取Cube结束时间
if [ ! -n "${end_date}" ]; then
	# 未传参则为当天00:00:00
	end=$[$(date -d "${today} 08:00:00" +%s) * 1000]
else
	# 传参则为参数那天的00:00:00
	end=$[$(date -d "${end_date} 08:00:00" +%s) * 1000]
fi

# 4、构建Cube
# 4.1、初始构建
if [ ${mode} == 'build' ]; then
	# 输出Cube信息
	echo "***************Rebuild Cube***************"
	echo "Cube       ${cube_name}"
	echo "User       ${user}"
	echo "Mode       ${mode}"

	# 构建Cube
	nohup \
	curl -X PUT \
	-H "Authorization: Basic ${usr}" \
	-H "Connect-Type: application/json" \
	-d '{"buildType":"BUILD"}' \
	http://kylin-host:port/kylin/api/cubes/${cube_name}/build \
	>dev/null 2>&1 &

# 4.2、增量构建
elif [ ${mode} == 'rebuild' ]; then
	# 输出Cube信息
	echo "***************Rebuild Cube***************"
	echo "Cube       ${cube_name}"
	echo "User       ${user}"
	echo "Mode       ${mode}"
	echo "EndTime    $(date -d @$[${end} / 1000 - 28800] "+%Y-%m-%d %H:%M:%S")"
	# 构建Cube
	nohup \
	curl -X PUT \
	-H "Authorization: Basic ${usr}" \
	-H "Connect-Type: application/json" \
	-d '{"endTime":'${end}', "buildType":"BUILD"}' \
	http://kylin-host:port/kylin/api/cubes/${cube_name}/rebuild \
	>dev/null 2>&1 &

# 4.3、全量刷新
elif [ ${mode} == 'refresh' ]; then
	# 输出Cube信息
	echo "***************Refresh Cube***************"
	echo "Cube       ${cube_name}"
	echo "User       ${user}"
	echo "Mode       ${mode}"
	echo "***************Refresh Cube***************"
	# 构建Cube
	nohup \
	curl -X PUT \
	-H "Authorization: Basic ${usr}" \
	-H "Connect-Type: application/json" \
	-d '{"buildType":"REFRESH"}' \
	http://kylin-host:port/kylin/api/cubes/${cube_name}/build \
	>dev/null 2>&1 &

else
	echo "Please set a mode! (such as -mode=build / -mode=rebuild / -mode=refresh)"
fi
```