# hive_sql
```python
# -*- coding: utf-8 -*-
import sys
import pandas as pd
import codecs

#stdout = sys.stdout
#reload(sys)
#sys.setdefaultencoding('utf-8')
#stdout = sys.stdout

# excel 文档中根据空行来区分表的范围

# 得到一个表的索引范围
def get_deli_list(df_new):
    delimeter_list = df_new[df_new['des'].isnull()].index.tolist()
    delimeter_list.insert(0, -1)
    delimeter_list.append(None)
    delimeter

    deli = []
    for i in range(1, len(delimeter_list)):
        deli.append([delimeter_list[i - 1] + 1, delimeter_list[i]])
    return deli


# 生成一张表的建表语句
def get_table_script(df_new):
    col_info = df_new.iloc[2:]
    # print col_info
    # col_info['sql'] = col_info.apply(lambda x: " " + x[2] + " " + x[3] + " comment '" + x[1] + "',", 1)
    tbl_info = df_new.iloc[0]

    # print tbl_info.iloc[2]+'..........'
    print( tbl_info.iloc[2]+'.........' )
    col_info['sql'] = col_info.apply(lambda x: " %s %s,"%( x[2], x[3]), 1 )
```