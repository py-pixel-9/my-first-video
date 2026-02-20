"""
Alpha Trend Master Pro - Backtest & Optimization
=================================================
Original: ATR Trailing Stop + EMA(1000) filter
Timeframe: M30
SL: 5% fixed, TP: 15~55% (5 levels)

Optimization tests:
1. Original strategy reproduction
2. RR ratio optimization (SL/TP variations)
3. ATR-based SL/TP vs fixed %
4. Single exit vs partial TP
5. Full period 2022~2026 yearly breakdown

Data: BTCUSDT_M5.csv → resampled to M30
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


def resample_ohlcv(df_5m, freq='30min'):
    df = df_5m.copy()
    df.index = pd.DatetimeIndex(df['timestamp'])
    ohlcv = df.resample(freq).agg({
        'open': 'first', 'high': 'max', 'low': 'min',
        'close': 'last', 'volume': 'sum',
    }).dropna()
    ohlcv['timestamp'] = ohlcv.index
    return ohlcv.reset_index(drop=True)


def calc_ema(values, period):
    return pd.Series(values).ewm(span=period, adjust=False).mean().values


def calc_atr(df, period=5):
    h = df['high'].values.astype(float)
    l = df['low'].values.astype(float)
    c = df['close'].values.astype(float)
    n = len(c)
    tr = np.zeros(n)
    tr[0] = h[0] - l[0]
    for i in range(1, n):
        tr[i] = max(h[i] - l[i], abs(h[i] - c[i-1]), abs(l[i] - c[i-1]))
    # RMA (Wilder's smoothing) like TradingView ta.atr
    atr = np.zeros(n)
    atr[period-1] = np.mean(tr[:period])
    for i in range(period, n):
        atr[i] = (atr[i-1] * (period - 1) + tr[i]) / period
    return atr


def calc_atr_trailing_stop(df, keyvalue=50.0, atr_period=5):
    """
    ATR Trailing Stop calculation (same as PineScript logic)
    nLoss = keyvalue * ATR
    Trailing stop follows price with nLoss distance
    """
    c = df['close'].values.astype(float)
    n = len(c)
    atr = calc_atr(df, atr_period)

    nLoss = keyvalue * atr
    xATRTrailingStop = np.zeros(n)

    for i in range(1, n):
        nl = nLoss[i]
        prev_stop = xATRTrailingStop[i-1]

        if c[i] > prev_stop and c[i-1] > prev_stop:
            xATRTrailingStop[i] = max(prev_stop, c[i] - nl)
        elif c[i] < prev_stop and c[i-1] < prev_stop:
            xATRTrailingStop[i] = min(prev_stop, c[i] + nl)
        elif c[i] > prev_stop:
            xATRTrailingStop[i] = c[i] - nl
        else:
            xATRTrailingStop[i] = c[i] + nl

    return xATRTrailingStop, atr


def generate_signals_alpha(df, keyvalue=50.0, atr_period=5, ema_period=1000):
    """
    Generate Alpha Trend Master signals
    LONG: close crosses above ATR trailing stop AND close > EMA(1000)
    SHORT: close crosses below ATR trailing stop AND close < EMA(1000)
    """
    c = df['close'].values.astype(float)
    n = len(c)

    trailing_stop, atr = calc_atr_trailing_stop(df, keyvalue, atr_period)
    ema_filter = calc_ema(c, ema_period)

    signals = []
    start_bar = max(ema_period, atr_period) + 10

    for i in range(start_bar, n):
        # Cross above trailing stop
        if c[i] > trailing_stop[i] and c[i-1] <= trailing_stop[i-1]:
            if c[i] > ema_filter[i]:  # EMA filter
                signals.append({
                    'bar': i, 'direction': 'LONG', 'price': c[i],
                    'atr': atr[i], 'trailing_stop': trailing_stop[i],
                    'timestamp': df['timestamp'].iloc[i]
                })
        # Cross below trailing stop
        elif c[i] < trailing_stop[i] and c[i-1] >= trailing_stop[i-1]:
            if c[i] < ema_filter[i]:  # EMA filter
                signals.append({
                    'bar': i, 'direction': 'SHORT', 'price': c[i],
                    'atr': atr[i], 'trailing_stop': trailing_stop[i],
                    'timestamp': df['timestamp'].iloc[i]
                })

    return signals, trailing_stop, atr, ema_filter


def backtest_fixed_pct(df, signals, sl_pct=0.05, tp_pct=0.15, fee=0.0006, max_hold=200, risk=0.02):
    """Backtest with fixed percentage SL/TP"""
    c = df['close'].values.astype(float)
    h = df['high'].values.astype(float)
    l = df['low'].values.astype(float)
    n = len(c)
    trades = []; equity = 10000.0
    eq_curve = [{'bar':0,'equity':equity,'timestamp':df['timestamp'].iloc[0]}]
    i = 0
    while i < len(signals):
        sig = signals[i]; eb=sig['bar']; ep=sig['price']; d=sig['direction']
        sl_dist = ep * sl_pct
        if sl_dist <= 0: i+=1; continue

        if d == 'LONG':
            sl = ep * (1 - sl_pct)
            tp = ep * (1 + tp_pct)
        else:
            sl = ep * (1 + sl_pct)
            tp = ep * (1 - tp_pct)

        rk = abs(ep - sl)
        if rk <= 0 or rk/ep > 0.10: i+=1; continue
        ps = (equity * risk) / rk; ec = ep * ps * fee

        xb=xp=xr=None
        for bar in range(eb+1, min(eb+max_hold, n)):
            if d == 'LONG':
                if l[bar] <= sl: xb,xp,xr=bar,sl,'SL'; break
                if h[bar] >= tp: xb,xp,xr=bar,tp,'TP'; break
            else:
                if h[bar] >= sl: xb,xp,xr=bar,sl,'SL'; break
                if l[bar] <= tp: xb,xp,xr=bar,tp,'TP'; break
        if xb is None: xb=min(eb+max_hold-1,n-1); xp=c[xb]; xr='TIME'
        xc = xp * ps * fee
        pnl = ((xp-ep) if d=='LONG' else (ep-xp)) * ps - ec - xc
        equity += pnl
        if equity <= 0: equity = 0
        eq_curve.append({'bar':xb,'equity':equity,'timestamp':df['timestamp'].iloc[min(xb,n-1)]})
        trades.append({'entry_time':sig['timestamp'],'exit_time':df['timestamp'].iloc[min(xb,n-1)],
                       'direction':d,'entry_price':ep,'exit_price':xp,'pnl':pnl,
                       'exit_reason':xr,'hold_bars':xb-eb})
        if equity <= 0: break
        while i+1<len(signals) and signals[i+1]['bar']<=xb: i+=1
        i+=1
    return trades, eq_curve, equity


def backtest_atr_based(df, signals, sl_atr_mult=2.0, tp_atr_mult=6.0, fee=0.0006, max_hold=200, risk=0.02):
    """Backtest with ATR-based SL/TP"""
    c = df['close'].values.astype(float)
    h = df['high'].values.astype(float)
    l = df['low'].values.astype(float)
    n = len(c)
    trades = []; equity = 10000.0
    eq_curve = [{'bar':0,'equity':equity,'timestamp':df['timestamp'].iloc[0]}]
    i = 0
    while i < len(signals):
        sig = signals[i]; eb=sig['bar']; ep=sig['price']; d=sig['direction']; a=sig['atr']
        if np.isnan(a) or a <= 0: i+=1; continue

        if d == 'LONG':
            sl = ep - a * sl_atr_mult
            tp = ep + a * tp_atr_mult
        else:
            sl = ep + a * sl_atr_mult
            tp = ep - a * tp_atr_mult

        rk = abs(ep - sl)
        if rk <= 0 or rk/ep > 0.10: i+=1; continue
        ps = (equity * risk) / rk; ec = ep * ps * fee

        xb=xp=xr=None
        for bar in range(eb+1, min(eb+max_hold, n)):
            if d == 'LONG':
                if l[bar] <= sl: xb,xp,xr=bar,sl,'SL'; break
                if h[bar] >= tp: xb,xp,xr=bar,tp,'TP'; break
            else:
                if h[bar] >= sl: xb,xp,xr=bar,sl,'SL'; break
                if l[bar] <= tp: xb,xp,xr=bar,tp,'TP'; break
        if xb is None: xb=min(eb+max_hold-1,n-1); xp=c[xb]; xr='TIME'
        xc = xp * ps * fee
        pnl = ((xp-ep) if d=='LONG' else (ep-xp)) * ps - ec - xc
        equity += pnl
        if equity <= 0: equity = 0
        eq_curve.append({'bar':xb,'equity':equity,'timestamp':df['timestamp'].iloc[min(xb,n-1)]})
        trades.append({'entry_time':sig['timestamp'],'exit_time':df['timestamp'].iloc[min(xb,n-1)],
                       'direction':d,'entry_price':ep,'exit_price':xp,'pnl':pnl,
                       'exit_reason':xr,'hold_bars':xb-eb})
        if equity <= 0: break
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
        run+=p; pk=max(pk,run)
        dd=(pk-run)/pk*100 if pk>0 else 0
        mdd=max(mdd,dd)
    lwr = len(longs[longs['pnl']>0])/len(longs)*100 if len(longs)>0 else 0
    swr = len(shorts[shorts['pnl']>0])/len(shorts)*100 if len(shorts)>0 else 0
    mc=cc=0
    for p in df_t['pnl']:
        if p<=0: cc+=1; mc=max(mc,cc)
        else: cc=0
    aw = wins['pnl'].mean() if len(wins)>0 else 0
    al = abs(losses['pnl'].mean()) if len(losses)>0 else 0
    # yearly
    df_t['year'] = pd.to_datetime(df_t['entry_time']).dt.year
    yearly = {}
    for yr, grp in df_t.groupby('year'):
        yr_w = grp[grp['pnl']>0]; yr_l = grp[grp['pnl']<=0]
        yr_pf = yr_w['pnl'].sum()/abs(yr_l['pnl'].sum()) if len(yr_l)>0 and yr_l['pnl'].sum()!=0 else 999
        yearly[yr] = {'trades':len(grp),'wr':len(yr_w)/len(grp)*100,'pf':yr_pf,'pnl':grp['pnl'].sum(),
                       'longs':len(grp[grp['direction']=='LONG']),'shorts':len(grp[grp['direction']=='SHORT'])}
    return {'label':label,'total':total,'wr':wr,'lc':len(longs),'sc':len(shorts),
            'lwr':lwr,'swr':swr,'pf':pf,'pnl':tp_val,'eq':10000+tp_val,'mdd':mdd,
            'ah':df_t['hold_bars'].mean(),'max_consec_loss':mc,'aw':aw,'al':al,'yearly':yearly}


def print_result(s, show_yearly=True):
    if not s: print("  -> No trades"); return
    pf_str = f"{s['pf']:.2f}" if s['pf'] < 100 else "INF"
    print(f"  {s['label']}")
    print(f"    Trades:{s['total']}  WR:{s['wr']:.1f}%  PF:{pf_str}  P&L:${s['pnl']:,.0f}  "
          f"MDD:{s['mdd']:.1f}%  MaxStreak:{s['max_consec_loss']}  L:{s['lc']} S:{s['sc']}  "
          f"AvgWin:${s['aw']:,.0f}  AvgLoss:${s['al']:,.0f}  AvgHold:{s['ah']:.0f}bars")
    if show_yearly and s.get('yearly'):
        print(f"    {'Year':>6s} {'Trds':>5s} {'WR%':>6s} {'PF':>6s} {'P&L':>10s} {'L':>3s} {'S':>3s}")
        all_profit = True
        for yr in sorted(s['yearly'].keys()):
            y = s['yearly'][yr]
            pf_s = f"{y['pf']:.2f}" if y['pf'] < 100 else "INF"
            m = "+" if y['pnl'] > 0 else "-"
            if y['pnl'] <= 0: all_profit = False
            print(f"    {yr:>6d} {y['trades']:>5d} {y['wr']:>5.1f}% {pf_s:>6s} ${y['pnl']:>9,.0f} {m} {y['longs']:>3d} {y['shorts']:>3d}")
        if all_profit:
            print(f"    *** ALL YEARS PROFITABLE ***")


def plot_equity(eq_dict, output_dir, filename, title):
    fig, ax = plt.subplots(figsize=(18, 9))
    fig.patch.set_facecolor('#131722'); ax.set_facecolor('#131722')
    colors = ['#26a69a','#42a5f5','#ff7043','#ab47bc','#ffa726','#ef5350',
              '#66bb6a','#29b6f6','#ff8a65','#ce93d8','#78909c','#4db6ac']
    for i,(label,eq) in enumerate(eq_dict.items()):
        if not eq: continue
        ax.plot([e['timestamp'] for e in eq],[e['equity'] for e in eq],
                color=colors[i%len(colors)], linewidth=1.5, label=label, alpha=0.9)
    ax.axhline(y=10000, color='#787b86', linestyle='--', alpha=0.5)
    for yr in [2022,2023,2024,2025,2026]:
        ax.axvline(x=pd.Timestamp(f'{yr}-01-01'), color='#363c4e', linestyle=':', alpha=0.3)
    ax.set_title(title, color='#e6edf3', fontsize=14, fontweight='bold')
    ax.set_ylabel('Equity ($)', color='#e6edf3'); ax.tick_params(colors='#787b86')
    ax.legend(loc='upper left', fontsize=7, facecolor='#1e222d', edgecolor='#363c4e', labelcolor='#e6edf3')
    ax.grid(True, alpha=0.1, color='#363c4e')
    for s in ax.spines.values(): s.set_color('#363c4e')
    fpath = os.path.join(output_dir, filename)
    fig.savefig(fpath, dpi=120, bbox_inches='tight', facecolor='#131722')
    plt.close(fig); return fpath


def main():
    print("=" * 130)
    print("ALPHA TREND MASTER PRO - BACKTEST & OPTIMIZATION")
    print("Base: ATR Trailing Stop(50, ATR5) + EMA(1000) | M30 | 2022~2026")
    print("=" * 130)

    df_m5 = pd.read_csv(DATA_M5)
    df_m5['timestamp'] = pd.to_datetime(df_m5['timestamp'])
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Resample to M30
    df_30m = resample_ohlcv(df_m5, '30min')
    print(f"\n  M30: {len(df_30m):,} bars | {df_30m['timestamp'].iloc[0]} ~ {df_30m['timestamp'].iloc[-1]}")

    # Also prepare higher TF for comparison
    df_1h = resample_ohlcv(df_m5, '1h')
    df_2h = resample_ohlcv(df_m5, '2h')
    print(f"  1H:  {len(df_1h):,} bars")
    print(f"  2H:  {len(df_2h):,} bars")

    # ============================================================
    # Phase 1: Original strategy reproduction
    # ============================================================
    print("\n" + "=" * 130)
    print("PHASE 1: ORIGINAL STRATEGY (SL 5%, TP levels at 15/25/35/45/55%)")
    print("=" * 130)

    # Generate signals on M30
    sigs_30m, ts_30m, atr_30m, ema_30m = generate_signals_alpha(df_30m, keyvalue=50.0, atr_period=5, ema_period=1000)
    print(f"\n  M30 signals: {len(sigs_30m)}")
    print(f"  LONG: {sum(1 for s in sigs_30m if s['direction']=='LONG')}  SHORT: {sum(1 for s in sigs_30m if s['direction']=='SHORT')}")

    # Test each TP level as single exit
    print(f"\n  --- Original fixed % SL/TP (single exit at each TP level) ---")
    all_results = []
    all_eq = {}

    for tp_name, tp_pct in [("TP1(15%)", 0.15), ("TP2(25%)", 0.25), ("TP3(35%)", 0.35),
                              ("TP4(45%)", 0.45), ("TP5(55%)", 0.55)]:
        label = f"M30 Original SL5%/{tp_name}"
        trades, eq, _ = backtest_fixed_pct(df_30m, sigs_30m, sl_pct=0.05, tp_pct=tp_pct,
                                            max_hold=500, risk=0.02)
        s = analyze(trades, label)
        if s:
            all_results.append(s)
            all_eq[label] = eq
        print_result(s)
        print()

    # ============================================================
    # Phase 2: RR Optimization with fixed % SL/TP
    # ============================================================
    print("\n" + "=" * 130)
    print("PHASE 2: RR OPTIMIZATION (Fixed % SL/TP)")
    print("=" * 130)

    # Test various SL/TP % combinations
    rr_configs = [
        # (sl_pct, tp_pct, label)
        (0.02, 0.06, "SL2%/TP6% RR1:3"),
        (0.02, 0.08, "SL2%/TP8% RR1:4"),
        (0.02, 0.10, "SL2%/TP10% RR1:5"),
        (0.03, 0.09, "SL3%/TP9% RR1:3"),
        (0.03, 0.12, "SL3%/TP12% RR1:4"),
        (0.03, 0.15, "SL3%/TP15% RR1:5"),
        (0.04, 0.12, "SL4%/TP12% RR1:3"),
        (0.04, 0.16, "SL4%/TP16% RR1:4"),
        (0.04, 0.20, "SL4%/TP20% RR1:5"),
        (0.05, 0.10, "SL5%/TP10% RR1:2"),
        (0.05, 0.15, "SL5%/TP15% RR1:3"),
        (0.05, 0.20, "SL5%/TP20% RR1:4"),
        (0.05, 0.25, "SL5%/TP25% RR1:5"),
        (0.01, 0.03, "SL1%/TP3% RR1:3"),
        (0.01, 0.05, "SL1%/TP5% RR1:5"),
        (0.015, 0.06, "SL1.5%/TP6% RR1:4"),
        (0.015, 0.075, "SL1.5%/TP7.5% RR1:5"),
    ]

    print(f"\n  Testing {len(rr_configs)} fixed % configs...\n")
    header = f"  {'Strategy':<40s} {'Trds':>4s} {'WR%':>5s} {'PF':>6s} {'P&L':>10s} {'MDD%':>6s} {'Strk':>4s} {'AvgH':>5s}"
    print(header)
    print("  " + "-" * 90)

    for sl_p, tp_p, rr_label in rr_configs:
        label = f"M30 {rr_label}"
        trades, eq, _ = backtest_fixed_pct(df_30m, sigs_30m, sl_pct=sl_p, tp_pct=tp_p,
                                            max_hold=500, risk=0.02)
        s = analyze(trades, label)
        if s:
            all_results.append(s)
            all_eq[label] = eq
            pf_s = f"{s['pf']:.2f}" if s['pf'] < 100 else "INF"
            print(f"  {label:<40s} {s['total']:>4d} {s['wr']:>4.1f}% {pf_s:>6s} "
                  f"${s['pnl']:>9,.0f} {s['mdd']:>5.1f}% {s['max_consec_loss']:>4d} {s['ah']:>4.0f}b")
        else:
            print(f"  {label:<40s}  -> No trades")

    # ============================================================
    # Phase 3: ATR-based SL/TP
    # ============================================================
    print("\n\n" + "=" * 130)
    print("PHASE 3: ATR-BASED SL/TP")
    print("=" * 130)

    atr_configs = [
        (1.0, 3.0, "ATR SL1/TP3"),
        (1.0, 4.0, "ATR SL1/TP4"),
        (1.0, 5.0, "ATR SL1/TP5"),
        (1.5, 4.5, "ATR SL1.5/TP4.5"),
        (1.5, 6.0, "ATR SL1.5/TP6"),
        (1.5, 7.5, "ATR SL1.5/TP7.5"),
        (2.0, 6.0, "ATR SL2/TP6"),
        (2.0, 8.0, "ATR SL2/TP8"),
        (2.0, 10.0, "ATR SL2/TP10"),
        (3.0, 9.0, "ATR SL3/TP9"),
        (3.0, 12.0, "ATR SL3/TP12"),
        (3.0, 15.0, "ATR SL3/TP15"),
    ]

    print(f"\n  Testing {len(atr_configs)} ATR-based configs...\n")
    print(header)
    print("  " + "-" * 90)

    for sl_m, tp_m, atr_label in atr_configs:
        label = f"M30 {atr_label}"
        trades, eq, _ = backtest_atr_based(df_30m, sigs_30m, sl_atr_mult=sl_m, tp_atr_mult=tp_m,
                                            max_hold=500, risk=0.02)
        s = analyze(trades, label)
        if s:
            all_results.append(s)
            all_eq[label] = eq
            pf_s = f"{s['pf']:.2f}" if s['pf'] < 100 else "INF"
            print(f"  {label:<40s} {s['total']:>4d} {s['wr']:>4.1f}% {pf_s:>6s} "
                  f"${s['pnl']:>9,.0f} {s['mdd']:>5.1f}% {s['max_consec_loss']:>4d} {s['ah']:>4.0f}b")
        else:
            print(f"  {label:<40s}  -> No trades")

    # ============================================================
    # Phase 4: Different timeframes with same signals
    # ============================================================
    print("\n\n" + "=" * 130)
    print("PHASE 4: TIMEFRAME COMPARISON (same strategy, different TF)")
    print("=" * 130)

    for tf_name, df_tf, mh in [('M30', df_30m, 500), ('1H', df_1h, 250), ('2H', df_2h, 120)]:
        # Adjust EMA period: M30 EMA1000 ≈ 1H EMA500 ≈ 2H EMA250
        if tf_name == 'M30': ema_p = 1000
        elif tf_name == '1H': ema_p = 500
        else: ema_p = 250

        sigs, _, _, _ = generate_signals_alpha(df_tf, keyvalue=50.0, atr_period=5, ema_period=ema_p)
        print(f"\n  {tf_name} (EMA{ema_p}): {len(sigs)} signals")

        # Test best configs from Phase 2/3
        for sl_p, tp_p, rr_label in [(0.03, 0.12, "SL3%/TP12%"), (0.03, 0.15, "SL3%/TP15%"),
                                      (0.05, 0.15, "SL5%/TP15%"), (0.05, 0.25, "SL5%/TP25%")]:
            label = f"{tf_name} {rr_label}"
            trades, eq, _ = backtest_fixed_pct(df_tf, sigs, sl_pct=sl_p, tp_pct=tp_p,
                                                max_hold=mh, risk=0.02)
            s = analyze(trades, label)
            if s:
                all_results.append(s)
                all_eq[label] = eq
                pf_s = f"{s['pf']:.2f}" if s['pf'] < 100 else "INF"
                print(f"    {label:<40s} {s['total']:>4d} {s['wr']:>4.1f}% {pf_s:>6s} "
                      f"${s['pnl']:>9,.0f} {s['mdd']:>5.1f}% {s['max_consec_loss']:>4d} {s['ah']:>4.0f}b")

    # ============================================================
    # Phase 5: Sensitivity (keyvalue) optimization
    # ============================================================
    print("\n\n" + "=" * 130)
    print("PHASE 5: SENSITIVITY (keyvalue) OPTIMIZATION on M30")
    print("=" * 130)

    for kv in [20, 30, 40, 50, 60, 80, 100]:
        sigs_kv, _, _, _ = generate_signals_alpha(df_30m, keyvalue=kv, atr_period=5, ema_period=1000)
        # Test with best TP from Phase 2
        for sl_p, tp_p, rr_label in [(0.03, 0.12, "SL3/TP12"), (0.05, 0.15, "SL5/TP15")]:
            label = f"M30 KV{kv} {rr_label}"
            trades, eq, _ = backtest_fixed_pct(df_30m, sigs_kv, sl_pct=sl_p, tp_pct=tp_p,
                                                max_hold=500, risk=0.02)
            s = analyze(trades, label)
            if s:
                all_results.append(s)
                all_eq[label] = eq
                pf_s = f"{s['pf']:.2f}" if s['pf'] < 100 else "INF"
                print(f"  {label:<40s} sigs:{len(sigs_kv):>3d} {s['total']:>4d}t {s['wr']:>4.1f}% {pf_s:>6s} "
                      f"${s['pnl']:>9,.0f} {s['mdd']:>5.1f}% {s['max_consec_loss']:>4d}")

    # ============================================================
    # FINAL RANKINGS
    # ============================================================
    print("\n\n" + "=" * 130)
    print("FINAL RANKINGS (PF > 1.0, Trades >= 5)")
    print("=" * 130)

    valid = [r for r in all_results if r.get('pf', 0) > 1.0 and r.get('total', 0) >= 5]
    by_pnl = sorted(valid, key=lambda x: x['pnl'], reverse=True)

    print(f"\n  --- TOP 15 BY P&L (with yearly breakdown) ---")
    for i, s in enumerate(by_pnl[:15], 1):
        print(f"\n  #{i}")
        print_result(s, show_yearly=True)

    # Find strategies profitable in 3+ years
    print(f"\n\n  --- STRATEGIES PROFITABLE IN 3+ YEARS ---")
    for s in by_pnl:
        yearly = s.get('yearly', {})
        profit_yrs = sum(1 for yr in yearly if yearly[yr]['pnl'] > 0)
        s['profit_years'] = profit_yrs

    consistent = [s for s in by_pnl if s.get('profit_years', 0) >= 3]
    consistent.sort(key=lambda x: (x['profit_years'], x['pnl']), reverse=True)

    for i, s in enumerate(consistent[:10], 1):
        print(f"\n  #{i} [{s['profit_years']} profitable years]")
        print_result(s, show_yearly=True)

    # Risk scaling for top 3
    print(f"\n\n  --- RISK SCALING (Top 3) ---")
    for s in by_pnl[:3]:
        if not s: continue
        monthly = s['pnl'] / 48
        print(f"\n  {s['label']}")
        print(f"  {'Risk%':>8s} {'Monthly$':>10s} {'Annual%':>8s} {'MDD':>7s}")
        for rp in [2, 3, 5]:
            m = rp / 2.0
            print(f"  {rp:>7d}% ${monthly*m:>9.0f} {monthly*m*12/100:>7.1f}% {s['mdd']*m:>6.1f}%")

    # Charts
    print("\n\n[Charts] Generating...")
    # Top equity curves
    top_eq = {}
    for s in by_pnl[:8]:
        if s['label'] in all_eq:
            top_eq[s['label']] = all_eq[s['label']]
    if top_eq:
        p1 = plot_equity(top_eq, OUTPUT_DIR, 'alpha_trend_top.png',
                          'Alpha Trend Master: Top Strategies (2022~2026, Risk 2%)')
        print(f"  Top equity: {p1}")

    # Consistent strategies
    con_eq = {}
    for s in consistent[:6]:
        if s['label'] in all_eq:
            con_eq[s['label']] = all_eq[s['label']]
    if con_eq:
        p2 = plot_equity(con_eq, OUTPUT_DIR, 'alpha_trend_consistent.png',
                          'Alpha Trend: Most Consistent Strategies (2022~2026)')
        print(f"  Consistent: {p2}")

    print("\n" + "=" * 130)
    print("COMPLETE")
    print("=" * 130)


if __name__ == '__main__':
    main()
