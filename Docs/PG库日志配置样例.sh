#------------------------------------------------------------------------------
# ERROR REPORTING AND LOGGING
#------------------------------------------------------------------------------

# - Where to Log -

#log_destination = 'stderr'     
#                   # Valid values are combinations of                # stderr, csvlog, syslog, and eventlog四选一，默认stderr
                    # stderr, csvlog, syslog, and eventlog,           # 也可以使用csvlog，这样输出的就是一个csv文件，这个好处是
                    # depending on platform.  csvlog                  # csv文件可以作为外表表导入数据库进行检索
                    # requires logging_collector to be on.            # 这个参数有效的前提是logging_collector也必须打开为on

# This is used when logging to stderr:
logging_collector = on      
                    # Enable capturing of stderr and csvlog           #这个参数为on时，pg数据库就开始记录日志了，但是默认为off
                    # into log files. Required to be on for           #这个参数更改后需要restart数据库
                    # csvlogs.
                    # (change requires restart)

# These are only used if logging_collector is on:
log_directory = 'pg_log'        
                    # directory where log files are written,          # 该参数是配置日志的目录，可以是绝对目录，也可以是相对目录
                    # can be absolute or relative to PGDATA           # 相对目录要设置PGDATA的值，如果pg_log文件夹不存在要新建

log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log' 
                    # log file name pattern,                          # 该参数是配置log的名字，一般用这个就行了，不用修改
                    # can include strftime() escapes

#log_file_mode = 0600           
#                   # creation mode for log files,                    # 日志文件的权限，默认是600也不用更改
                    # begin with 0 to use octal notation

#log_truncate_on_rotation = off     
#                   # If on, an existing log file with the                 # 这个参数没必要开启，因为如果出现同名的日志文件，开启会
                    # same name as the new log file will be                # 清空原来日志，而不是在原来的基础上增加。但是在有一种情况
                    # truncated rather than appended to.                   # 下，可以设置为on，就是日志文件以星期格式命名，一周一轮回
                    # But such truncation only occurs on                   # 默认就保留了7天日志，这个是一个巧妙的日志处理方法。
                    # time-driven rotation, not on restarts
                    # or size-driven rotation.  Default is
                    # off, meaning append to existing files
                    # in all cases.

#log_rotation_age = 1d          
#                   # Automatic rotation of logfiles will                 # 单个日志的生存期，默认为1天，在日志文件没有达到log_rotation_size
                    # happen after that time.  0 disables.                # 时，一天只生成一个日志文件

#log_rotation_size = 10MB       
#                   # Automatic rotation of logfiles will                 # 单个日志文件大小，如果时间没有超过log_rotation_age，一个日志
                    # happen after that much log output.                  # 文件最大只能是10M，否则生成一个新的日志文件
                    # 0 disables.

# These are relevant when logging to syslog:
#syslog_facility = 'LOCAL0'                                             #这几个参数是在上面的log_destination设置为syslog需要配置的，很少用
#syslog_ident = 'postgres'
#syslog_sequence_numbers = on
#syslog_split_messages = on

# This is only relevant when logging to eventlog (win32):               # 这几个参数是在上面的log_destination设置为eventlog需要配置的，很少用
# (change requires restart)
#event_source = 'PostgreSQL'

# - When to Log -

#log_min_messages = warning     
                    # values in order of decreasing detail:              # 控制写到服务器日志里的信息的详细程度。有效值是DEBUG5， DEBUG4， 
                    #   debug5                                           # DEBUG3，DEBUG2，DEBUG1， INFO，NOTICE，WARNING， ERROR，LOG
                    #   debug4                                           # FATAL， and PANIC。每个级别都包含它后面的级别。越靠后的数值 
                    #   debug3                                           # 发往服务器日志的信息越少，缺省是WARNING。
                    #   debug2
                    #   debug1
                    #   info
                    #   notice
                    #   warning
                    #   error
                    #   log
                    #   fatal
                    #   panic

#log_min_error_statement = error    
                    # values in order of decreasing detail:
                    #   debug5                                           # 控制是否在服务器日志里输出那些导致错误条件的 SQL 语句。
                    #   debug4                                           # 所有导致一个特定级别(或者更高级别)错误的 SQL 语句都要
                    #   debug3                                           # 被记录。有效的值有DEBUG5， DEBUG4，DEBUG3， 
                    #   debug2                                           # DEBUG2，DEBUG1，INFO，NOTICE，WARNING，ERROR，LOG，FATAL
                    #   debug1                                           # ，和PANIC。缺省是ERROR，表示所有导致错误、致命错误、恐慌的
                    #   info                                             # SQL语句都将被记录。
                    #   notice
                    #   warning
                    #   error
                    #   log
                    #   fatal
                    #   panic (effectively off)

log_min_duration_statement = 0  
                    # -1 is disabled, 0 logs all statements              # 这个参数非常重要，是排查慢查询的好工具，-1是关闭记录这类日志
                    # and their durations, > 0 logs only                 # 0 是记录所有的查询SQL，如果设置为大于0（毫秒），则超过该值的
                    # statements running at least this number            # 执行时间的sql会记录下来
                    # of milliseconds


# - What to Log -

#debug_print_parse = off                                                 # 调试类的，没必要打开该类日志
#debug_print_rewritten = off
#debug_print_plan = off
#debug_pretty_print = on
#log_checkpoints = off                                                   # 记录发生检查点的日志
#log_connections = off                                                   # 记录客户连接的日志
#log_disconnections = off                                                # 记录客户断开的日志
#log_duration = off                                                      # 记录每条SQL语句执行完成消耗的时间，将此配置设置为on,用于统计
                                                                         # 哪些SQL语句耗时较长。一般用上面那个log_min_duration_statement即可

#log_error_verbosity = default      # terse, default, or verbose messages

#log_hostname = on

log_line_prefix = '%m %p %u %d %r %e'           
                    # special values:                                    # 日志输出格式（%m,%p实际意义配置文件中有解释）,可根据自己需要设置
                    #   %a = application name                            # （能够记录时间，用户名称，数据库名称，客户端IP和端口，sql语句方便定位问题）
                    #   %u = user name
                    #   %d = database name
                    #   %r = remote host and port
                    #   %h = remote host
                    #   %p = process ID
                    #   %t = timestamp without milliseconds
                    #   %m = timestamp with milliseconds
                    #   %n = timestamp with milliseconds (as a Unix epoch)
                    #   %i = command tag
                    #   %e = SQL state
                    #   %c = session ID
                    #   %l = session line number
                    #   %s = session start timestamp
                    #   %v = virtual transaction ID
                    #   %x = transaction ID (0 if none)
                    #   %q = stop here in non-session
                    #        processes
                    #   %% = '%'
                    # e.g. '<%u%%%d> '
                    
#log_lock_waits = off           # log lock waits >= deadlock_timeout   # 控制当一个会话等待时间超过deadlock_timeout而被锁时是否产生一个
                                                                       # 日志信息。在判断一个锁等待是否会影响性能时是有用的，缺省是off。
#log_statement = 'none'         # none, ddl, mod, all                  # none, ddl, mod, all ---- 控制记录哪些SQL语句。
                                                                       # none不记录，ddl记录所有数据定义命令，比如CREATE,ALTER,和DROP语句。
                                                                       # mod记录所有ddl语句,加上数据修改语句INSERT,UPDATE等,all记录所有执行的语句，
                                                                       # 将此配置设置为all可跟踪整个数据库执行的SQL语句。
#log_replication_commands = off

#log_temp_files = -1            
                    # log temporary files equal or larger
                    # than the specified size in kilobytes;
                    # -1 disables, 0 logs all temp files
log_timezone = 'PRC'                                                   # 日志时区，最好和服务器设置同一个时区，方便问题定位


# - Process Title -

#cluster_name = ''          # added to process titles if nonempty
                    # (change requires restart)
#update_process_title = on