# excel_hive_sql.py
```python
# -*- coding: utf-8 -*-
import sys
import pandas as pd
import codecs

# stdout = sys.stdout
# Python2使用以下代码配置编码为UTF-8，Python3不需要
#reload(sys)
#sys.setdefaultencoding('utf-8')
# stdout = sys.stdout

# excel 文档中根据空行来区分表的范围

# 得到一个表的索引范围(前半包围)
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
    col_info['sql'] = col_info.apply(lambda x:"  %s  %s  COMMENT '%s',"%(x[2], x[3], x[1]), 1)
    col_sql = '\n'.join(col_info['sql'].tolist())[:-1]
    # print col_sql
    tbl_info = df_new.iloc[0]

    table_sql = '''
DROP TABLE IF EXISTS {0};
CREATE TABLE IF NOT EXISTS {1} (
{2}
)
COMMENT '{3}'
STORED AS ORC;

    '''.format(tbl_info.iloc[2], tbl_info.iloc[2], col_sql, tbl_info.iloc[1])
    return table_sql.replace("'nan'", "''")


# 定义main方法
def main():
    file_name = sys.argv[1]
    db_type = 'hive'
    desti_name = file_name + '_hive.sql'

    # 读取文件，并将相邻行都是空行的，只保留一行空行
    df = pd.read_excel(file_name, header=None, names=['des', 'col_name_ch', 'col_name_eg', 'col_type'])
    df['col_1'] = df['col_name_eg'].shift(1)
    df_new = df[df['col_name_eg'].notnull() | df['col_1'].notnull()].reset_index(drop=True).drop('col_1', 1)

    # 得出表在dataframe中的索引范围
    deli_list = get_deli_list(df_new)

    # 生成SQL语句
    db_name = sys.argv[2]
    tbl_sqls = 'USE ' + db_name + ';'
    for i in deli_list:
        df_tbl = df_new.iloc[i[0]:i[1],]
        tbl_sqls = tbl_sqls + get_table_script(df_tbl)

    # 将结果写入文件
    with codecs.open(desti_name, "w", encoding='utf-8') as f:
        f.write(tbl_sqls)


if __name__ == '__main__':
    main()
```