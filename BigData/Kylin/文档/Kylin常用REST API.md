# Kylin常用REST API

* 官方文档：<http://kylin.apache.org/cn/docs/howto/howto_use_restapi.html>

* 用户登录验证

```bash
usr=$(python -c "import base64; print base64.standard_b64encode('${user}:${passwd}')")
curl -X POST \
    -H "Authorization: Basic ${usr}" \
    -H 'Content-Type: application/json;charset=UTF-8' \
    "http://${kylin_host}:${port}//kylin/api/user/authentication"
```

## 1、Model、Cube

### 1.1 Model

#### 1.1.1 创建Model

```bash
# desc_data 可通过 Web 页的 Model 详情中获取，" 替换为 \"
desc="{\"modelName\":\"\", \"project\":\"${project}\", \"modelDescData\":\"${desc_data}\"}"
curl -X POST \
    -H "Authorization: Basic ${usr}" \
    -H 'Content-Type: application/json;charset=UTF-8' \
    -d ${desc}
    "http://${kylin_host}:${port}/kylin/api/models"
```

#### 1.1.2 删除Model

```bash
curl -X DELETE \
    -H "Authorization: Basic ${usr}" \
    -H 'Content-Type: application/json;charset=UTF-8' \
    "http://${kylin_host}:${port}/kylin/api/models/${model_name}"
```

### 1.2 Cube

#### 1.2.1 创建Cube

```bash
# desc_data 可通过 Web 页的 Cube 详情中获取，" 替换为 \"
desc="{\"cubeName\":\"\", \"project\":\"${project}\", \"cubeDescData\":\"${desc_data}\"}"
curl -X POST \
    -H "Authorization: Basic ${usr}" \
    -H 'Content-Type: application/json;charset=UTF-8' \
    -d ${desc}
    "http://${kylin_host}:${port}/kylin/api/cubes"
```

#### 1.2.2 删除Cube

```bash
curl -X DELETE \
    -H "Authorization: Basic ${usr}" \
    -H 'Content-Type: application/json;charset=UTF-8' \
    "http://${kylin_host}:${port}/kylin/api/cubes/${cube_name}"
```

#### 1.2.3 设置Cube为不可用

```bash
curl -X PUT \
    -H "Authorization: Basic ${usr}" \
    -H 'Content-Type: application/json;charset=UTF-8' \
    "http://${kylin_host}:${port}/kylin/api/cubes/${cube_name}/disable"
```

#### 1.2.4 设置Cube为可用

```bash
curl -X PUT \
    -H "Authorization: Basic ${usr}" \
    -H 'Content-Type: application/json;charset=UTF-8' \
    "http://${kylin_host}:${port}/kylin/api/cubes/${cube_name}/enable"
```

#### 1.2.5 清空Cube数据

```bash
curl -X PUT \
    -H "Authorization: Basic ${usr}" \
    -H 'Content-Type: application/json;charset=UTF-8' \
    "http://${kylin_host}:${port}/kylin/api/cubes/${cube_name}/purge"
```

## 2、Jobs

### 2.1 下发Cube构建任务

#### 2.1.1 增量Cube

* 初始任务

```bash
curl -X PUT \
    -H "Authorization: Basic ${usr}" \
    -H 'Content-Type: application/json;charset=UTF-8' \
    -d '{"endTime":'"${end}"', "buildType":"BUILD"}' \
    "http://${kylin_host}:${port}/kylin/api/cubes/${cube_name}/build"
```

* 每日增量任务

```bash
curl -X PUT \
    -H "Authorization: Basic ${usr}" \
    -H 'Content-Type: application/json;charset=UTF-8' \
    -d '{"endTime":'"${end}"', "buildType":"BUILD"}' \
    "http://${kylin_host}:${port}/kylin/api/cubes/${cube_name}/rebuild"
```

#### 2.1.2 全量Cube

* 初始与增量相同，每日刷新任务

```bash
curl -X PUT \
    -H "Authorization: Basic ${usr}" \
    -H 'Content-Type: application/json;charset=UTF-8' \
    -d '{"endTime":'"${end}"', "buildType":"BUILD"}' \
    "http://${kylin_host}:${port}/kylin/api/cubes/${cube_name}/rebuild"
```

### 2.2 获取任务列表

```bash
curl -X GET \
    -H "Authorization: Basic ${usr}" \
    -H 'Content-Type: application/json;charset=UTF-8' \
    "http://${kylin_host}:${port}/kylin/api/jobs"
```

### 2.3 获取任务详情

```bash
# job_id 即任务页面每个任务唯一的UUID
curl -X GET \
    -H "Authorization: Basic ${usr}" \
    -H 'Content-Type: application/json;charset=UTF-8' \
    "http://${kylin_host}:${port}/kylin/api/jobs/${job_id}"
```

## 3、Table

### 3.1 加载表

```bash
# tables 格式：库名.表名，多张表使用 , 分隔
curl -X POST \
    -H "Authorization: Basic ${usr}" \
    -H 'Content-Type: application/json;charset=UTF-8' \
    -d '{"calculate": "true"}'
    "http://${kylin_host}:${port}/kylin/api/tables/${tables}/${project}"
```

### 3.2 卸载表

```bash
# tables 格式：库名.表名，多张表使用 , 分隔
curl -X DELETE \
    -H "Authorization: Basic ${usr}" \
    -H 'Content-Type: application/json;charset=UTF-8' \
    "http://${kylin_host}:${port}/kylin/api/tables/${tables}/${project}"
```

## 4、元数据缓存

### 4.1 全局刷新

```bash
curl -X PUT \
    -H "Authorization: Basic ${usr}" \
    -H 'Content-Type: application/json;charset=UTF-8' \
    "http://${kylin_host}:${port}/kylin/api/cache/announce/all/update"
```

### 4.2 项目级刷新

```bash
curl -X PUT \
    -H "Authorization: Basic ${usr}" \
    -H 'Content-Type: application/json;charset=UTF-8' \
    "http://${kylin_host}:${port}/kylin/api/cache/project/${project}/update"
```
