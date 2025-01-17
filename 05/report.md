# 数据库概论第五次实习作业

> 原梓轩 2200010825
> 陈润璘 2200010848
> 任子博 2200010626

## 任务一：索引调优
首先创建`testIndex(id, A, B, C)`，使用`insert_random_data(in num_rows int)`例程插入100000条随机数据

### 1. 比较A列建立索引前后的分组和自连接查询性能
在建立索引前，分组查询使用369ms，自连接查询使用79ms；建立索引后，分组查询使用274ms，自连接查询使用131ms。
发现自连接查询在建立索引后性能反而下降，推测可能是由于索引的建立导致了额外的开销，同时由于插入的随机数据相同值较多，导致索引的效果不明显。
### 2. 比较A列索引和(A, B)联合索引在`select B where A`类型查询上的性能
在A列建立索引后，查询使用了474ms；在(A, B)联合索引建立后，查询使用了79ms，性能提升明显。
### 3. 观察C列上函数索引的效果
目前版本的MySQL不支持函数索引，因此我们需要手动维护一个列来存储substring(C, 2, 3)的值，模拟函数索引的效果。
对于`select from where Substring(C, 2, 3)='ABC'`查询，建立索引前使用了323ms，建立索引后使用了82ms，性能提升明显。
对于`select from where Substring(C, 2, 2)='AB'`查询，建立索引前使用了284ms，建立索引后使用了290ms，性能没有提升。


## 任务二：最大并发间隔问题的不同实现方式性能比较
本部分详见`part2.ipynb`，sql语句单独放在`part2.sql`中。

首先创建表`sessions(keycol, app, usr, host, starttime, endtime)`，并在`starttime`和`endtime`上建立索引。

随后定义函数`insert_data(n)`用于插入随机数据。

依据给出的脚本，实现了集合、游标、窗口函数三种不同的查询，封装在函数`select_with_set()`, `select_with_cursor()`, `select_with_window()`中。

最后使用不同数据规模，对比三种查询的性能并绘制图表。观察发现，随着数据规模的增大，集合查询的性能下降严重，总体性能游标优于窗口优于集合。
![](./pic/output.png)

## 任务三：SQL Hint

在这个任务中，我们分别测试了三种不同的 SQL Hint，分别是 `INDEX_MERGE`, `JOIN_ORDER` 和 `HASH_JOIN`。

### INDEX_MERGE

`INDEX_MERGE` 是一种优化方法，它可以将多个索引的结果集合并起来，从而减少查询的时间。在这个任务中，我们使用了 `INDEX_MERGE` 来优化查询。

在我们的例子中，表 `t1` 中的两个字段 `a` 和 `b` 都有索引，它们的取值范围是[1, 1000]，表中共有 10000 条记录。使用 `INDEX_MERGE` 的查询语句如下：

```mysql
select /*+ INDEX_MERGE(t1 idx_t1_a, idx_t1_b)*/ *
from t1
where a > 500
  and b > 500;
```

在测试中，不使用 `INDEX_MERGE` 和使用 `INDEX_MERGE` 的查询时间分别为 64ms 和 46ms，使用 `explain` 查看他们的查询计划可以发现使用 `INDEX_MERGE` 时，预估需要查询的行数大约是不适用时的一半，并且 `Extra` 中增加了 `Using index condition;`，说明使用了索引条件。

### JOIN_ORDER

使用 `JOIN_ORDER` 可以指定查询的表的连接顺序，从而减少查询的时间。在我们的例子中，我们连接两个分别有 20000，50000 条记录的表 `t1` 和 `t2`，使用 `JOIN_ORDER` 的查询语句如下：

```mysql
select /*+ JOIN_ORDER(t1, t2) */ *
from t1
         join t2 on t1.a = t2.a
    and t1.b = t2.b;
```

在测试中，不使用 `JOIN_ORDER` 和使用 `JOIN_ORDER` 的查询时间分别为 1s 931ms 和 1s 107ms，使用 `explain` 查看他们的查询计划可以发现使用 `JOIN_ORDER` 时，连接的顺序发生了变化，记录数较少的表 `t1` 先被连接，这样可以减少连接的次数。

### HASH_JOIN

使用 `HASH_JOIN` 可以指定两个表连接时的连接方式为哈希连接，在测试中，我们使用两个分别有 100，1000 条记录的表 `t3` 和 `t4` 进行连接，使用 `HASH_JOIN` 的查询语句如下：

```mysql
select /*+ HASH_JOIN(t3, t4) */ *
from t3
         join t4 on t3.a = t4.a;
```

在测试中，不使用 `HASH_JOIN` 和使用 `HASH_JOIN` 的查询时间分别为 97ms 和 58ms，使用 `explain` 查看他们的查询计划可以发现使用 `HASH_JOIN` 时，`Extra` 中增加了 `Using join buffer (Hash Join);`，说明使用了哈希连接加快了查询的速度。

## 任务四

我们在这里测试事务并发控制的功能，我们使用了两个事务，分别是 `T1` 和 `T2`，`T1` 会对表 `t1` 进行更新操作，`T2` 会对表 `t1` 进行查询操作。

这里以银行转账为例，测试不同隔离等级下的并发控制。

- 方案一：对 bank_trans 和 bank_user 表的修改放在同一个事务中

这种方式是最容易实现的，但是由于事务比较大，触发冲突的可能就会增大，从而会导致一定的性能问题。

- 方案二：对 bank_trans 和 bank_user 表的修改放在两个事务中

分解事务可以减少事务的大小，从而减少冲突的可能，对提高性能有所帮助（前提是在并行下，否则反而会降低效率）。不过，这样可能会事务的一致性造成一定的影响。

- 方案三：对 bank_user 表的修改封装为消息，把事务内容批量更新到 bank_user 表中。我们这里给 bank_trans 表附加一个 processed列，初始事务插入这个表时，processed 列设为 0，一个事务条目一旦被定期更新过了，就把 processed 列设为 1，这样下次定期更新的时候就只更新 processed 为 0 的记录。

封装为消息之后，最佳方式是维护一个消息队列，不过这种方式实现起来比较复杂，我们这里简单的采用了一个定时任务的方式，每隔 100 次查询更新一次 bank_user 表。这种方式的好处批量处理是减少了写冲突，可以有效提高性能。不过，在必要的情况下需要及时刷新消息队列，否则可能会导致数据不一致。
