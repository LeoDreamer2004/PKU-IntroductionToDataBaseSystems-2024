drop table if exists stock;
create table stock(
    ts_code varchar(15),
    trade_date date,
    open float,
    high float,
    low float,
    close float,
    pre_close float,
    pct_chg float,
    vol float,
    amount float
);


# 计算alpha005
# Alpha#5: (rank((open - (sum(vwap, 10) / 10))) * (-1 * abs(rank((close - vwap)))))
# 计算vwap
with vwap_calc as (
    select
        ts_code,
        trade_date,
        amount / vol as vwap
   from
        stock
),
# 计算sum(vwap, 10) / 10
avg_vwap as (
    select
        ts_code,
        trade_date,
        avg(vwap) over (partition by ts_code order by trade_date rows between 9 preceding and current row) as avg_vwap_10
    from
        vwap_calc
),
# 计算rank((open - (sum(vwap, 10) / 10)))
ranked_open as (
    select
        a.ts_code,
        a.trade_date,
        rank() over (partition by a.trade_date order by s.open - avg_vwap_10) as rank_open
    from
        avg_vwap as a
    join
        stock as s on a.ts_code = s.ts_code and a.trade_date = s.trade_date
),
# 计算rank((close - vwap))
ranked_close as (
    select
        a.ts_code,
        a.trade_date,
        rank() over (partition by a.trade_date order by s.close - a.vwap) as rank_close
    from
        vwap_calc as a
    join
        stock as s on a.ts_code = s.ts_code and a.trade_date = s.trade_date
),
# 使用上述结果，完成alpha005的计算
final_calc as (
    select
        o.ts_code,
        o.trade_date,
        o.rank_open,
        cast(o.rank_open as signed) * -1 * cast(abs(c.rank_close) as signed) as alpha5
    from
        ranked_open o
    join
        ranked_close c on o.ts_code = c.ts_code and o.trade_date = c.trade_date
)

select
    ts_code,
    trade_date,
    alpha5
from
    final_calc
order by
    alpha5 desc;


# 计算alpha033
# Alpha#33: rank((-1 * ((1 - (open / close))^1)))
# 计算(-1 * ((1 - (open / close))^1))
with alpha_calc as (
    select
        ts_code,
        trade_date,
        -1 * (1 - (open / close)) as alpha_value
    from
        stock
),

# 计算rank((-1 * ((1 - (open / close))^1)))
ranked_alpha as (
    select
        ts_code,
        trade_date,
        rank() over (partition by trade_date order by alpha_value) as alpha33
    from
        alpha_calc
)

select
    ts_code,
    trade_date,
    alpha33
from
    ranked_alpha
order by
    alpha33 desc;



# 计算alpha057
# Alpha#57: (0 - (1 * ((close - vwap) / decay_linear(rank(ts_argmax(close, 30)), 2))))
# 计算vwap
with vwap_calc as (
    select
        ts_code,
        trade_date,
        amount / vol as vwap
   from
        stock
),
# 计算每只股票过去30天收盘价排名，用于计算ts_argmax
max_close_calc as (
    select
        ts_code,
        trade_date,
        row_number() over (partition by ts_code order by close desc ) as close_rank
    from
        stock
    where
        trade_date > date_sub(trade_date, interval 30 day)
),
# 计算ts_argmax(close, 30)
ts_argmax_calc as (
    select
        ts_code,
        trade_date,
        max(close_rank) over (partition by ts_code order by trade_date rows between 29 preceding and current row ) as ts_argmax
    from
        max_close_calc
),
# 计算rank(ts_argmax(close, 30)),按照trade_date分组
rank_calc as (
    select
        ts_code,
        trade_date,
        ts_argmax,
        rank() over (partition by trade_date order by ts_argmax) as ts_argmax_rank
    from
        ts_argmax_calc
),
# 计算decay_linear(rank(ts_argmax(close, 30)), 2)
decay_linear as (
    select
        ts_code,
        trade_date,
        ts_argmax_rank,
        ts_argmax_rank / (sum(ts_argmax_rank) over (partition by ts_code order by trade_date rows between 1 preceding and current row)) as decayed_rank
    from
        rank_calc
),
# 使用上述结果，完成alpha057的计算
final_calc as (
    select
        s.ts_code,
        s.trade_date,
        s.close,
        v.vwap,
        d.decayed_rank,
        (s.close - v.vwap) / d.decayed_rank AS alpha57_value
    from
        stock s
    join
        vwap_calc v on s.ts_code = v.ts_code and s.trade_date = v.trade_date
    join
        decay_linear d on s.ts_code = d.ts_code and s.trade_date = d.trade_date
)

select
    ts_code,
    trade_date,
    0 - alpha57_value as alpha57
from
    final_calc
order by
    alpha57 desc;



# 计算alpha083
# Alpha#83: ((rank(delay(((high - low) / (sum(close, 5) / 5)), 2)) * rank(rank(volume))) / (((high -
# low) / (sum(close, 5) / 5)) / (vwap - close)))
# 计算vwap
with vwap_calc as (
    select
        ts_code,
        trade_date,
        amount / vol AS vwap
    from
        stock
),
# 计算5日均值, sum(close, 5) / 5
avg_close as (
    select
        ts_code,
        trade_date,
        avg(close) over (partition by ts_code order by trade_date rows between 4 preceding and current row) as avg_close_5
    from
        stock
),
# 计算delay(((high - low) / (sum(close, 5) / 5)), 2)
delay_calc as (
    select
        s.ts_code,
        s.trade_date,
        (high - low) / avg_close_5 as ratio,
        lag((high - low) / avg_close_5, 2) over (partition by s.ts_code order by s.trade_date) as delayed_ratio
    from
        stock s
    join
        avg_close r on s.ts_code = r.ts_code and s.trade_date = r.trade_date
),
# 计算rank(delay(((high - low) / (sum(close, 5) / 5)), 2))
ranked_delayed_ratio as (
    select
        ts_code,
        trade_date,
        rank() over (partition by trade_date order by delayed_ratio)  as rank_delayed_ratio
    from
        delay_calc
),
# 计算rank(volume)
ranked_volume as (
    select
        ts_code,
        trade_date,
        rank() over (partition by trade_date order by vol)  as rank_volume
    from
        stock
),
# 计算rank(rank(volume))
ranked_rank_volume as (
    select
        ts_code,
        trade_date,
        rank() over (partition by trade_date order by rank_volume)  as rank_rank_volume
    from
        ranked_volume
),
# 计算 (high - low) / avg_close_5 和 (vwap - close)
ratios as (
    select
        s.ts_code,
        s.trade_date,
        (s.high - s.low) / r.avg_close_5 as ratio_high_low,
        v.vwap - s.close as vwap_close_diff
    from
        stock s
    join
        avg_close r on s.ts_code = r.ts_code and s.trade_date = r.trade_date
    join
        vwap_calc v on s.ts_code = v.ts_code and s.trade_date = v.trade_date
),
# 使用上述结果，完成alpha083的计算
alpha_83_calc as (
    select
        r.ts_code,
        r.trade_date,
        (rd.rank_delayed_ratio * rv.rank_rank_volume) / (r.ratio_high_low / r.vwap_close_diff) as alpha83
    from
        ratios r
    join
        ranked_delayed_ratio rd on r.ts_code = rd.ts_code and r.trade_date = rd.trade_date
    join
        ranked_rank_volume rv on r.ts_code = rv.ts_code and r.trade_date = rv.trade_date
)
select
    ts_code,
    trade_date,
    alpha83
from
    alpha_83_calc
order by
    alpha83 desc;



