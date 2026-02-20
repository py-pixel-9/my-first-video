"""
Multi-Timeframe EMA Trend Filter Backtest
==========================================
핵심 아이디어: 상위 타임프레임 EMA로 "큰 추세" 방향을 확인하고
             그 방향으로만 진입 → 역추세 매매 차단

테스트 조합:
1. 기본 전략: Supertrend(10,3) + EMA(20/50) + ADX Filter (1.5H/2H)
2. 상위 TF 필터:
   - 일봉 EMA 200 (가장 전통적)
   - 4H EMA 100
   - 4H EMA 200
   - 일봉 EMA 50 + 200 (골든/데드 크로스)
   - 일봉 EMA 50 단독
3. 필터 모드:
   - Direction Only: 상위TF EMA 위=롱만, 아래=숏만
   - Trend Alignment: 상위TF EMA 방향 + 기울기 확인

전체 기간: 2022-01 ~ 2026-02 (4년+)
연도별 분석 포함
"""

import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import os
import warnings
warnings.filterwarnings('ignore')

DATA_M5 = os.path.join(os.path.dirname(__file__), 'data', 'BTCUSDT_M5.csv')
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), 'backtest_results')


def resample_ohlcv(df_5m, freq='2h'):
    df = df_5m.copy()
    df.index = pd.DatetimeIndex(df['timestamp'])
    ohlcv = df.resample(freq).agg({
        'open': 'first', 'high': 'max', 'low': 'min',
        'close': 'last', 'volume': 'sum',
    }).dropna()
    ohlcv['timestamp'] = ohlcv.index
    return ohlcv.reset_index(drop=True)


def calc_supertrend(df, atr_period=10, multiplier=3.0):
    h = df['high'].values.astype(float)
    l = df['low'].values.astype(float)
    c = df['close'].values.astype(float)
    n = len(c)
    tr = np.zeros(n); tr[0] = h[0] - l[0]
    for i in range(1, n):
        tr[i] = max(h[i] - l[i], abs(h[i] - c[i-1]), abs(l[i] - c[i-1]))
    atr = pd.Series(tr).rolling(atr_period).mean().values
    src = (h + l) / 2
    up = np.zeros(n); dn = np.zeros(n)
    trend = np.ones(n, dtype=int)
    up[0] = src[0] - multiplier * (atr[0] if not np.isnan(atr[0]) else tr[0])
    dn[0] = src[0] + multiplier * (atr[0] if not np.isnan(atr[0]) else tr[0])
    for i in range(1, n):
        a = atr[i] if not np.isnan(atr[i]) else tr[i]
        up[i] = src[i] - multiplier * a
        if c[i-1] > up[i-1]: up[i] = max(up[i], up[i-1])
        dn[i] = src[i] + multiplier * a
        if c[i-1] < dn[i-1]: dn[i] = min(dn[i], dn[i-1])
        if trend[i-1] == -1 and c[i] > dn[i-1]: trend[i] = 1
        elif trend[i-1] == 1 and c[i] < up[i-1]: trend[i] = -1
        else: trend[i] = trend[i-1]
    st_buy = np.zeros(n, dtype=bool); st_sell = np.zeros(n, dtype=bool)
    for i in range(1, n):
        if trend[i] == 1 and trend[i-1] == -1: st_buy[i] = True
        elif trend[i] == -1 and trend[i-1] == 1: st_sell[i] = True
    return trend, up, dn, st_buy, st_sell, atr


def calc_ema(values, period):
    return pd.Series(values).ewm(span=period, adjust=False).mean().values


def calc_adx(df, period=14):
    h = df['high'].values.astype(float)
    l = df['low'].values.astype(float)
    c = df['close'].values.astype(float)
    n = len(c)
    tr = np.zeros(n); tr[0] = h[0] - l[0]
    for i in range(1, n):
        tr[i] = max(h[i] - l[i], abs(h[i] - c[i-1]), abs(l[i] - c[i-1]))
    plus_dm = np.zeros(n); minus_dm = np.zeros(n)
    for i in range(1, n):
        up_move = h[i] - h[i-1]; down_move = l[i-1] - l[i]
        if up_move > down_move and up_move > 0: plus_dm[i] = up_move
        if down_move > up_move and down_move > 0: minus_dm[i] = down_move
    atr_s = np.zeros(n); plus_dm_s = np.zeros(n); minus_dm_s = np.zeros(n)
    if period < n:
        atr_s[period] = np.sum(tr[1:period+1])
        plus_dm_s[period] = np.sum(plus_dm[1:period+1])
        minus_dm_s[period] = np.sum(minus_dm[1:period+1])
    for i in range(period+1, n):
        atr_s[i] = atr_s[i-1] - (atr_s[i-1]/period) + tr[i]
        plus_dm_s[i] = plus_dm_s[i-1] - (plus_dm_s[i-1]/period) + plus_dm[i]
        minus_dm_s[i] = minus_dm_s[i-1] - (minus_dm_s[i-1]/period) + minus_dm[i]
    plus_di = np.zeros(n); minus_di = np.zeros(n)
    for i in range(period, n):
        if atr_s[i] > 0:
            plus_di[i] = 100*plus_dm_s[i]/atr_s[i]; minus_di[i] = 100*minus_dm_s[i]/atr_s[i]
    dx = np.zeros(n)
    for i in range(period, n):
        di_sum = plus_di[i]+minus_di[i]
        if di_sum > 0: dx[i] = 100*abs(plus_di[i]-minus_di[i])/di_sum
    adx = np.zeros(n); start = period*2
    if start < n:
        adx[start] = np.mean(dx[period+1:start+1])
        for i in range(start+1, n): adx[i] = (adx[i-1]*(period-1)+dx[i])/period
    return adx, plus_di, minus_di


def map_htf_to_ltf(df_ltf, htf_timestamps, htf_values):
    """Map higher timeframe values to lower timeframe bars"""
    result = np.full(len(df_ltf), np.nan)
    htf_ts = pd.DatetimeIndex(htf_timestamps)
    ltf_ts = pd.DatetimeIndex(df_ltf['timestamp'])

    htf_idx = 0
    for i in range(len(df_ltf)):
        # Find the most recent HTF bar that closed before/at this LTF bar
        while htf_idx < len(htf_ts) - 1 and htf_ts[htf_idx + 1] <= ltf_ts[i]:
            htf_idx += 1
        if htf_ts[htf_idx] <= ltf_ts[i]:
            result[i] = htf_values[htf_idx]
    return result


def generate_signals_mtf(df_ltf, df_htf_list, filter_config,
                          atr_period=10, multiplier=3.0, ema_fast=20, ema_slow=50,
                          adx_period=14, adx_threshold=None):
    """
    Generate signals with multi-timeframe EMA filter.

    filter_config: dict with keys:
        'type': 'direction' or 'trend_align' or 'dual_ema' or 'none'
        'htf_df': higher TF dataframe
        'ema_period': EMA period on HTF
        'ema_period2': second EMA period (for dual_ema)
        'slope_bars': bars to check slope (for trend_align)
    """
    c = df_ltf['close'].values.astype(float)
    n = len(c)
    trend, up, dn, st_buy, st_sell, atr = calc_supertrend(df_ltf, atr_period, multiplier)
    ema_f = calc_ema(c, ema_fast)
    ema_s = calc_ema(c, ema_slow)
    adx_values, _, _ = calc_adx(df_ltf, adx_period)

    # Calculate HTF EMA filter
    filter_type = filter_config.get('type', 'none')
    htf_long_ok = np.ones(n, dtype=bool)
    htf_short_ok = np.ones(n, dtype=bool)

    if filter_type != 'none':
        htf_df = filter_config['htf_df']
        htf_close = htf_df['close'].values.astype(float)

        if filter_type == 'direction':
            # Price above HTF EMA = long only, below = short only
            ema_p = filter_config['ema_period']
            htf_ema = calc_ema(htf_close, ema_p)
            # Map to LTF
            ltf_htf_ema = map_htf_to_ltf(df_ltf, htf_df['timestamp'], htf_ema)
            ltf_htf_close = map_htf_to_ltf(df_ltf, htf_df['timestamp'], htf_close)

            for i in range(n):
                if np.isnan(ltf_htf_ema[i]) or np.isnan(ltf_htf_close[i]):
                    htf_long_ok[i] = False
                    htf_short_ok[i] = False
                else:
                    htf_long_ok[i] = ltf_htf_close[i] > ltf_htf_ema[i]
                    htf_short_ok[i] = ltf_htf_close[i] < ltf_htf_ema[i]

        elif filter_type == 'trend_align':
            # Price above HTF EMA + EMA slope is up = long, opposite = short
            ema_p = filter_config['ema_period']
            slope_bars = filter_config.get('slope_bars', 5)
            htf_ema = calc_ema(htf_close, ema_p)
            ltf_htf_ema = map_htf_to_ltf(df_ltf, htf_df['timestamp'], htf_ema)
            ltf_htf_close = map_htf_to_ltf(df_ltf, htf_df['timestamp'], htf_close)

            # Also need lagged EMA for slope
            htf_ema_lagged = np.roll(htf_ema, slope_bars)
            htf_ema_lagged[:slope_bars] = np.nan
            ltf_htf_ema_lag = map_htf_to_ltf(df_ltf, htf_df['timestamp'], htf_ema_lagged)

            for i in range(n):
                if np.isnan(ltf_htf_ema[i]) or np.isnan(ltf_htf_close[i]) or np.isnan(ltf_htf_ema_lag[i]):
                    htf_long_ok[i] = False
                    htf_short_ok[i] = False
                else:
                    ema_rising = ltf_htf_ema[i] > ltf_htf_ema_lag[i]
                    ema_falling = ltf_htf_ema[i] < ltf_htf_ema_lag[i]
                    price_above = ltf_htf_close[i] > ltf_htf_ema[i]
                    price_below = ltf_htf_close[i] < ltf_htf_ema[i]
                    htf_long_ok[i] = price_above and ema_rising
                    htf_short_ok[i] = price_below and ema_falling

        elif filter_type == 'dual_ema':
            # HTF EMA fast > EMA slow = long, opposite = short (Golden/Dead cross)
            ema_p1 = filter_config['ema_period']   # fast (e.g., 50)
            ema_p2 = filter_config['ema_period2']   # slow (e.g., 200)
            htf_ema1 = calc_ema(htf_close, ema_p1)
            htf_ema2 = calc_ema(htf_close, ema_p2)
            ltf_htf_ema1 = map_htf_to_ltf(df_ltf, htf_df['timestamp'], htf_ema1)
            ltf_htf_ema2 = map_htf_to_ltf(df_ltf, htf_df['timestamp'], htf_ema2)
            ltf_htf_close = map_htf_to_ltf(df_ltf, htf_df['timestamp'], htf_close)

            for i in range(n):
                if np.isnan(ltf_htf_ema1[i]) or np.isnan(ltf_htf_ema2[i]):
                    htf_long_ok[i] = False
                    htf_short_ok[i] = False
                else:
                    htf_long_ok[i] = ltf_htf_ema1[i] > ltf_htf_ema2[i]  # golden cross state
                    htf_short_ok[i] = ltf_htf_ema1[i] < ltf_htf_ema2[i]  # dead cross state

        elif filter_type == 'triple_ema':
            # Price > EMA50 > EMA100 > EMA200 = strong uptrend (long only)
            # Price < EMA50 < EMA100 < EMA200 = strong downtrend (short only)
            htf_ema50 = calc_ema(htf_close, 50)
            htf_ema100 = calc_ema(htf_close, 100)
            htf_ema200 = calc_ema(htf_close, 200)
            ltf_50 = map_htf_to_ltf(df_ltf, htf_df['timestamp'], htf_ema50)
            ltf_100 = map_htf_to_ltf(df_ltf, htf_df['timestamp'], htf_ema100)
            ltf_200 = map_htf_to_ltf(df_ltf, htf_df['timestamp'], htf_ema200)
            ltf_c = map_htf_to_ltf(df_ltf, htf_df['timestamp'], htf_close)

            for i in range(n):
                if np.isnan(ltf_50[i]) or np.isnan(ltf_200[i]) or np.isnan(ltf_c[i]):
                    htf_long_ok[i] = False
                    htf_short_ok[i] = False
                else:
                    # Relaxed: price above EMA200 = long ok
                    htf_long_ok[i] = ltf_c[i] > ltf_200[i]
                    htf_short_ok[i] = ltf_c[i] < ltf_200[i]

    signals = []
    start_bar = max(ema_slow, atr_period, adx_period*2) + 1
    for i in range(start_bar, n):
        if st_buy[i] and ema_f[i] > ema_s[i]:
            if adx_threshold is not None and adx_values[i] < adx_threshold: continue
            if not htf_long_ok[i]: continue
            signals.append({'bar':i,'direction':'LONG','price':c[i],'atr':atr[i],
                           'adx':adx_values[i],'timestamp':df_ltf['timestamp'].iloc[i]})
        elif st_sell[i] and ema_f[i] < ema_s[i]:
            if adx_threshold is not None and adx_values[i] < adx_threshold: continue
            if not htf_short_ok[i]: continue
            signals.append({'bar':i,'direction':'SHORT','price':c[i],'atr':atr[i],
                           'adx':adx_values[i],'timestamp':df_ltf['timestamp'].iloc[i]})
    return signals, atr


def backtest_fixed(df, signals, sl_m=2.0, tp_m=6.0, fee=0.0006, max_hold=60, risk=0.02):
    c = df['close'].values.astype(float)
    h = df['high'].values.astype(float)
    l = df['low'].values.astype(float)
    n = len(c)
    trades = []; equity = 10000.0
    eq_curve = [{'bar':0,'equity':equity,'timestamp':df['timestamp'].iloc[0]}]
    i = 0
    while i < len(signals):
        sig = signals[i]; eb=sig['bar']; ep=sig['price']; d=sig['direction']; a=sig['atr']
        if np.isnan(a) or a<=0: i+=1; continue
        sl = ep-a*sl_m if d=='LONG' else ep+a*sl_m
        tp = ep+a*tp_m if d=='LONG' else ep-a*tp_m
        rk = abs(ep-sl)
        if rk<=0 or rk/ep>0.05: i+=1; continue
        ps = (equity*risk)/rk; ec = ep*ps*fee
        xb=xp=xr=None
        for bar in range(eb+1, min(eb+max_hold, n)):
            if d=='LONG':
                if l[bar]<=sl: xb,xp,xr=bar,sl,'SL'; break
                if h[bar]>=tp: xb,xp,xr=bar,tp,'TP'; break
            else:
                if h[bar]>=sl: xb,xp,xr=bar,sl,'SL'; break
                if l[bar]<=tp: xb,xp,xr=bar,tp,'TP'; break
        if xb is None: xb=min(eb+max_hold-1,n-1); xp=c[xb]; xr='TIME'
        xc = xp*ps*fee
        pnl = ((xp-ep) if d=='LONG' else (ep-xp))*ps - ec - xc
        equity += pnl
        if equity<=0: equity=0
        eq_curve.append({'bar':xb,'equity':equity,'timestamp':df['timestamp'].iloc[min(xb,n-1)]})
        trades.append({'entry_time':sig['timestamp'],'exit_time':df['timestamp'].iloc[min(xb,n-1)],
                       'direction':d,'entry_price':ep,'exit_price':xp,'pnl':pnl,
                       'exit_reason':xr,'hold_bars':xb-eb,'adx_at_entry':sig.get('adx',0)})
        if equity<=0: break
        while i+1<len(signals) and signals[i+1]['bar']<=xb: i+=1
        i+=1
    return trades, eq_curve, equity


def analyze(trades, label=""):
    if not trades: return {}
    df_t = pd.DataFrame(trades)
    total = len(df_t)
    wins = df_t[df_t['pnl']>0]; losses = df_t[df_t['pnl']<=0]
    longs = df_t[df_t['direction']=='LONG']; shorts = df_t[df_t['direction']=='SHORT']
    wr = len(wins)/total*100
    pf = wins['pnl'].sum()/abs(losses['pnl'].sum()) if len(losses)>0 and losses['pnl'].sum()!=0 else 999
    tp_val = df_t['pnl'].sum()
    mdd=0; pk=10000; run=10000
    for p in df_t['pnl']:
        run+=p
        if run>pk: pk=run
        dd=(pk-run)/pk*100 if pk>0 else 0
        if dd>mdd: mdd=dd
    lwr = len(longs[longs['pnl']>0])/len(longs)*100 if len(longs)>0 else 0
    swr = len(shorts[shorts['pnl']>0])/len(shorts)*100 if len(shorts)>0 else 0
    mc=0; cc=0
    for p in df_t['pnl']:
        if p<=0: cc+=1; mc=max(mc,cc)
        else: cc=0
    aw = wins['pnl'].mean() if len(wins)>0 else 0
    al = abs(losses['pnl'].mean()) if len(losses)>0 else 0

    # yearly breakdown
    df_t['year'] = pd.to_datetime(df_t['entry_time']).dt.year
    yearly = {}
    for yr, grp in df_t.groupby('year'):
        yr_wins = grp[grp['pnl']>0]
        yr_losses = grp[grp['pnl']<=0]
        yr_pf = yr_wins['pnl'].sum()/abs(yr_losses['pnl'].sum()) if len(yr_losses)>0 and yr_losses['pnl'].sum()!=0 else 999
        yearly[yr] = {
            'trades': len(grp),
            'wr': len(yr_wins)/len(grp)*100 if len(grp)>0 else 0,
            'pf': yr_pf,
            'pnl': grp['pnl'].sum(),
            'longs': len(grp[grp['direction']=='LONG']),
            'shorts': len(grp[grp['direction']=='SHORT']),
        }

    return {'label':label,'total':total,'wr':wr,'lc':len(longs),'sc':len(shorts),
            'lwr':lwr,'swr':swr,'pf':pf,'pnl':tp_val,'eq':10000+tp_val,'mdd':mdd,
            'ah':df_t['hold_bars'].mean(),'max_consec_loss':mc,
            'aw':aw,'al':al,'avg_adx':df_t['adx_at_entry'].mean(),
            'yearly': yearly}


def print_yearly(s):
    """Print yearly breakdown"""
    if not s or 'yearly' not in s: return
    yearly = s['yearly']
    years = sorted(yearly.keys())
    print(f"    {'Year':>6s} {'Trds':>5s} {'WR%':>6s} {'PF':>6s} {'P&L':>10s} {'L':>4s} {'S':>4s}")
    print(f"    {'-'*50}")
    all_profitable = True
    for yr in years:
        y = yearly[yr]
        pf_str = f"{y['pf']:>5.2f}" if y['pf'] < 100 else "  INF"
        marker = "+" if y['pnl'] > 0 else "-"
        if y['pnl'] <= 0: all_profitable = False
        print(f"    {yr:>6d} {y['trades']:>5d} {y['wr']:>5.1f}% {pf_str} ${y['pnl']:>9,.0f} {marker}  {y['longs']:>3d}  {y['shorts']:>3d}")
    return all_profitable


def plot_results(eq_dict, output_dir, filename, title):
    fig, ax = plt.subplots(figsize=(18, 9))
    fig.patch.set_facecolor('#131722'); ax.set_facecolor('#131722')
    colors = ['#26a69a','#42a5f5','#ff7043','#ab47bc','#ffa726','#ef5350',
              '#66bb6a','#29b6f6','#ff8a65','#ce93d8','#78909c','#4db6ac',
              '#8d6e63','#26c6da','#d4e157','#7e57c2']
    for i,(label,eq) in enumerate(eq_dict.items()):
        if not eq: continue
        ax.plot([e['timestamp'] for e in eq],[e['equity'] for e in eq],
                color=colors[i%len(colors)], linewidth=1.5, label=label, alpha=0.9)
    ax.axhline(y=10000, color='#787b86', linestyle='--', alpha=0.5)
    # Year markers
    for yr in [2022, 2023, 2024, 2025, 2026]:
        ax.axvline(x=pd.Timestamp(f'{yr}-01-01'), color='#363c4e', linestyle=':', alpha=0.3)
        ax.text(pd.Timestamp(f'{yr}-01-01'), ax.get_ylim()[1]*0.95, str(yr),
                color='#787b86', fontsize=9, ha='left')
    ax.set_title(title, color='#e6edf3', fontsize=14, fontweight='bold')
    ax.set_ylabel('Equity ($)', color='#e6edf3')
    ax.tick_params(colors='#787b86')
    ax.legend(loc='upper left', fontsize=7, facecolor='#1e222d', edgecolor='#363c4e',
              labelcolor='#e6edf3', ncol=2)
    ax.grid(True, alpha=0.1, color='#363c4e')
    for s in ax.spines.values(): s.set_color('#363c4e')
    fpath = os.path.join(output_dir, filename)
    fig.savefig(fpath, dpi=120, bbox_inches='tight', facecolor='#131722')
    plt.close(fig); return fpath


def main():
    print("=" * 140)
    print("MULTI-TIMEFRAME EMA TREND FILTER BACKTEST")
    print("Base: Supertrend(10,3) + EMA(20/50) | Full period: 2022-01 ~ 2026-02")
    print("Goal: Filter out counter-trend trades using higher TF EMAs")
    print("=" * 140)

    df_m5 = pd.read_csv(DATA_M5)
    df_m5['timestamp'] = pd.to_datetime(df_m5['timestamp'])
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # ============================================================
    # Resample all needed timeframes
    # ============================================================
    print("\n[Phase 1] Resampling timeframes...")

    df_90m = resample_ohlcv(df_m5, '90min')
    df_2h = resample_ohlcv(df_m5, '2h')
    df_4h = resample_ohlcv(df_m5, '4h')
    df_1d = resample_ohlcv(df_m5, '1D')

    # Full period (use all available data, no filtering)
    print(f"  90min: {len(df_90m):,} bars")
    print(f"  2H:    {len(df_2h):,} bars")
    print(f"  4H:    {len(df_4h):,} bars")
    print(f"  Daily: {len(df_1d):,} bars")
    print(f"  Period: {df_90m['timestamp'].iloc[0]} ~ {df_90m['timestamp'].iloc[-1]}")

    # ============================================================
    # Define test configurations
    # ============================================================
    print("\n[Phase 2] Testing configurations...")

    configs = []

    # For each entry TF (1.5H, 2H)
    for entry_tf_name, entry_df, max_hold in [('1.5H', df_90m, 80), ('2H', df_2h, 60)]:
        for adx_th in [None, 20]:
            adx_label = f"ADX>{adx_th}" if adx_th else "NoADX"

            # Baseline: no HTF filter
            configs.append({
                'label': f"{entry_tf_name} {adx_label} NoFilter",
                'entry_df': entry_df, 'max_hold': max_hold,
                'adx_threshold': adx_th,
                'filter': {'type': 'none'}
            })

            # HTF Filter: Daily EMA200 direction
            configs.append({
                'label': f"{entry_tf_name} {adx_label} D-EMA200",
                'entry_df': entry_df, 'max_hold': max_hold,
                'adx_threshold': adx_th,
                'filter': {'type': 'direction', 'htf_df': df_1d, 'ema_period': 200}
            })

            # HTF Filter: Daily EMA50 direction
            configs.append({
                'label': f"{entry_tf_name} {adx_label} D-EMA50",
                'entry_df': entry_df, 'max_hold': max_hold,
                'adx_threshold': adx_th,
                'filter': {'type': 'direction', 'htf_df': df_1d, 'ema_period': 50}
            })

            # HTF Filter: 4H EMA200 direction
            configs.append({
                'label': f"{entry_tf_name} {adx_label} 4H-EMA200",
                'entry_df': entry_df, 'max_hold': max_hold,
                'adx_threshold': adx_th,
                'filter': {'type': 'direction', 'htf_df': df_4h, 'ema_period': 200}
            })

            # HTF Filter: 4H EMA100 direction
            configs.append({
                'label': f"{entry_tf_name} {adx_label} 4H-EMA100",
                'entry_df': entry_df, 'max_hold': max_hold,
                'adx_threshold': adx_th,
                'filter': {'type': 'direction', 'htf_df': df_4h, 'ema_period': 100}
            })

            # HTF Filter: Daily EMA200 + slope (trend alignment)
            configs.append({
                'label': f"{entry_tf_name} {adx_label} D-EMA200+slope",
                'entry_df': entry_df, 'max_hold': max_hold,
                'adx_threshold': adx_th,
                'filter': {'type': 'trend_align', 'htf_df': df_1d, 'ema_period': 200, 'slope_bars': 5}
            })

            # HTF Filter: Daily EMA50/200 dual (Golden/Dead cross)
            configs.append({
                'label': f"{entry_tf_name} {adx_label} D-GoldenCross",
                'entry_df': entry_df, 'max_hold': max_hold,
                'adx_threshold': adx_th,
                'filter': {'type': 'dual_ema', 'htf_df': df_1d, 'ema_period': 50, 'ema_period2': 200}
            })

            # HTF Filter: 4H EMA50/200 dual
            configs.append({
                'label': f"{entry_tf_name} {adx_label} 4H-GoldenCross",
                'entry_df': entry_df, 'max_hold': max_hold,
                'adx_threshold': adx_th,
                'filter': {'type': 'dual_ema', 'htf_df': df_4h, 'ema_period': 50, 'ema_period2': 200}
            })

            # HTF Filter: Daily triple EMA (50/100/200) - relaxed version
            configs.append({
                'label': f"{entry_tf_name} {adx_label} D-TripleEMA",
                'entry_df': entry_df, 'max_hold': max_hold,
                'adx_threshold': adx_th,
                'filter': {'type': 'triple_ema', 'htf_df': df_1d}
            })

    # SL/TP variations for best filters
    for sl_m, tp_m, rr_label in [(1.5, 6.0, "SL1.5/TP6"), (2.0, 6.0, "SL2/TP6"),
                                   (1.5, 7.5, "SL1.5/TP7.5"), (2.0, 8.0, "SL2/TP8")]:
        for entry_tf_name, entry_df, max_hold in [('1.5H', df_90m, 80), ('2H', df_2h, 60)]:
            # Only test with Daily EMA200 (most likely winner) + ADX>20
            configs.append({
                'label': f"{entry_tf_name} ADX>20 D-EMA200 {rr_label}",
                'entry_df': entry_df, 'max_hold': max_hold,
                'adx_threshold': 20,
                'sl_m': sl_m, 'tp_m': tp_m,
                'filter': {'type': 'direction', 'htf_df': df_1d, 'ema_period': 200}
            })

    print(f"  Total configs: {len(configs)}\n")

    # ============================================================
    # Run all tests
    # ============================================================
    all_results = []
    all_eq = {}

    header = f"  {'#':>3s} {'Strategy':<48s} {'Sigs':>4s} {'Trds':>4s} {'WR%':>5s} {'PF':>6s} {'P&L':>10s} {'MDD%':>6s} {'Strk':>4s} {'L':>3s} {'S':>3s}"
    print(header)
    print("  " + "-" * 110)

    for idx, cfg in enumerate(configs):
        sl_m = cfg.get('sl_m', 1.5)
        tp_m = cfg.get('tp_m', 6.0)

        sigs, _ = generate_signals_mtf(
            cfg['entry_df'], None, cfg['filter'],
            atr_period=10, multiplier=3.0, ema_fast=20, ema_slow=50,
            adx_period=14, adx_threshold=cfg['adx_threshold']
        )

        trades, eq, _ = backtest_fixed(cfg['entry_df'], sigs,
                                        sl_m=sl_m, tp_m=tp_m,
                                        max_hold=cfg['max_hold'], risk=0.02)
        s = analyze(trades, cfg['label'])

        if s:
            all_results.append(s)
            all_eq[cfg['label']] = eq
            pf_str = f"{s['pf']:>5.2f}" if s['pf'] < 100 else "   INF"
            print(f"  {idx+1:>3d} {s['label']:<48s} {len(sigs):>4d} {s['total']:>4d} {s['wr']:>4.1f}% {pf_str} "
                  f"${s['pnl']:>9,.0f} {s['mdd']:>5.1f}% {s['max_consec_loss']:>4d} {s['lc']:>3d} {s['sc']:>3d}")
        else:
            print(f"  {idx+1:>3d} {cfg['label']:<48s} {len(sigs):>4d}  -> No trades")

    # ============================================================
    # Rankings
    # ============================================================
    print("\n" + "=" * 140)
    print("PHASE 3: RANKINGS (Full Period 2022~2026)")
    print("=" * 140)

    valid = [r for r in all_results if r.get('pf', 0) > 1.0 and r.get('total', 0) >= 10]

    # --- Rank by P&L ---
    print("\n--- TOP 15 BY TOTAL P&L ---")
    by_pnl = sorted(valid, key=lambda x: x['pnl'], reverse=True)
    for i, s in enumerate(by_pnl[:15], 1):
        monthly = s['pnl'] / 48  # ~48 months
        print(f"\n  #{i} {s['label']}")
        print(f"     Trades:{s['total']}  WR:{s['wr']:.1f}%  PF:{s['pf']:.2f}  P&L:${s['pnl']:,.0f}  "
              f"MDD:{s['mdd']:.1f}%  MaxStreak:{s['max_consec_loss']}  Monthly:${monthly:.0f}")
        all_profitable = print_yearly(s)
        if all_profitable:
            print(f"     *** ALL YEARS PROFITABLE ***")

    # --- Rank by consistency (all years profitable) ---
    print("\n\n--- STRATEGIES WITH ALL YEARS PROFITABLE ---")
    consistent = []
    for s in valid:
        yearly = s.get('yearly', {})
        if all(yearly[yr]['pnl'] > 0 for yr in yearly):
            consistent.append(s)

    if consistent:
        consistent.sort(key=lambda x: x['pnl'], reverse=True)
        for i, s in enumerate(consistent, 1):
            monthly = s['pnl'] / 48
            print(f"\n  #{i} {s['label']}")
            print(f"     Trades:{s['total']}  WR:{s['wr']:.1f}%  PF:{s['pf']:.2f}  P&L:${s['pnl']:,.0f}  "
                  f"MDD:{s['mdd']:.1f}%  Monthly:${monthly:.0f}")
            print_yearly(s)
    else:
        print("  -> No strategy was profitable in ALL years")
        # Show strategies profitable in 3+ years
        print("\n--- STRATEGIES PROFITABLE IN 3+ YEARS ---")
        three_plus = []
        for s in valid:
            yearly = s.get('yearly', {})
            profitable_years = sum(1 for yr in yearly if yearly[yr]['pnl'] > 0)
            s['profitable_years'] = profitable_years
            if profitable_years >= 3:
                three_plus.append(s)

        three_plus.sort(key=lambda x: (x['profitable_years'], x['pnl']), reverse=True)
        for i, s in enumerate(three_plus[:15], 1):
            monthly = s['pnl'] / 48
            print(f"\n  #{i} [{s['profitable_years']}/4+ yrs] {s['label']}")
            print(f"     Trades:{s['total']}  WR:{s['wr']:.1f}%  PF:{s['pf']:.2f}  P&L:${s['pnl']:,.0f}  "
                  f"MDD:{s['mdd']:.1f}%  Monthly:${monthly:.0f}")
            print_yearly(s)

    # ============================================================
    # Risk scaling for best strategies
    # ============================================================
    print("\n\n" + "=" * 140)
    print("PHASE 4: RISK SCALING FOR BEST STRATEGIES")
    print("=" * 140)

    best = by_pnl[:5] if by_pnl else []
    for s in best:
        monthly_base = s['pnl'] / 48
        print(f"\n  {s['label']}")
        print(f"  {'Risk%':>8s} {'Monthly$':>10s} {'Annual$':>10s} {'Annual%':>8s} {'MDD':>7s}")
        print(f"  {'-'*50}")
        for risk_pct in [2, 3, 5]:
            mult = risk_pct / 2.0
            mo = monthly_base * mult
            annual = mo * 12
            annual_pct = annual / 10000 * 100
            mdd = s['mdd'] * mult
            print(f"  {risk_pct:>7d}% ${mo:>9.0f} ${annual:>9.0f} {annual_pct:>7.1f}% {mdd:>6.1f}%")

    # ============================================================
    # Charts
    # ============================================================
    print("\n\n[Charts] Generating...")

    # Chart 1: Top strategies equity curves (full period)
    top_eq = {}
    for s in by_pnl[:8]:
        if s['label'] in all_eq:
            top_eq[s['label']] = all_eq[s['label']]

    if top_eq:
        p1 = plot_results(top_eq, OUTPUT_DIR, 'mtf_ema_top_equity.png',
                          'Multi-TF EMA Filter: Top Strategies (2022~2026, Risk 2%)')
        print(f"  Top equity: {p1}")

    # Chart 2: Best consistent strategies
    if consistent:
        con_eq = {}
        for s in consistent[:6]:
            if s['label'] in all_eq:
                con_eq[s['label']] = all_eq[s['label']]
        if con_eq:
            p2 = plot_results(con_eq, OUTPUT_DIR, 'mtf_ema_consistent.png',
                              'All-Years-Profitable Strategies (2022~2026, Risk 2%)')
            print(f"  Consistent equity: {p2}")
    elif three_plus:
        con_eq = {}
        for s in three_plus[:6]:
            if s['label'] in all_eq:
                con_eq[s['label']] = all_eq[s['label']]
        if con_eq:
            p2 = plot_results(con_eq, OUTPUT_DIR, 'mtf_ema_best_consistency.png',
                              'Best Consistency Strategies (3+ Profitable Years, 2022~2026)')
            print(f"  Best consistency equity: {p2}")

    # Chart 3: Filter comparison (same base strategy, different filters)
    filter_compare_eq = {}
    for key in ['2H ADX>20 NoFilter', '2H ADX>20 D-EMA200', '2H ADX>20 D-EMA50',
                '2H ADX>20 4H-EMA200', '2H ADX>20 D-GoldenCross', '2H ADX>20 D-EMA200+slope']:
        if key in all_eq:
            filter_compare_eq[key] = all_eq[key]
    if filter_compare_eq:
        p3 = plot_results(filter_compare_eq, OUTPUT_DIR, 'mtf_filter_comparison.png',
                          '2H ADX>20: Filter Comparison (2022~2026)')
        print(f"  Filter comparison: {p3}")

    print("\n" + "=" * 140)
    print("TEST COMPLETE")
    print("=" * 140)


if __name__ == '__main__':
    main()
