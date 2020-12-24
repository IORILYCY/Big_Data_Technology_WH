import base64
f=open('E:\\GitHub\\Big_Data_Technology_WH\\Notes\\BigData\\CDH\\pictures\\snipaste_20201224_200150.png','rb') #二进制方式打开图文件
ls_f=base64.b64encode(f.read()) #读取文件内容，转换为base64编码
f.close()
print(ls_f)