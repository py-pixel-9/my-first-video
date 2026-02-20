"""
Trade Frequency Optimization Backtest
======================================
목표: 거래 빈도를 늘려 월 수익률을 높이면서 퀄리티 유지

테스트 축:
1. 타임프레임: 1H / 1.5H / 2H (빈도 vs 퀄리티 트레이드오프)
2. ADX 기준: None / 15 / 20 (필터 느슨 → 거래 증가)
3. RR 비율: SL1.5/TP6(1:4), SL1.5/TP7.5(1:5), SL2/TP6(1:3),
            SL1.5/TP9(1:6), SL2/TP8(1:4), SL2/TP10(1:5)

기간: 2024-2025 (2년) | Risk: 2% & 5% 비교 | Fee: 0.06%/side
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
    tr = np.zeros(n)
    tr[0] = h[0] - l[0]
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


def generate_signals(df, atr_period=10, multiplier=3.0, ema_fast=20, ema_slow=50,
                     adx_period=14, adx_threshold=None):
    c = df['close'].values.astype(float)
    n = len(c)
    trend, up, dn, st_buy, st_sell, atr = calc_supertrend(df, atr_period, multiplier)
    ema_f = calc_ema(c, ema_fast); ema_s = calc_ema(c, ema_slow)
    adx_values, _, _ = calc_adx(df, adx_period)
    signals = []
    start_bar = max(ema_slow, atr_period, adx_period*2) + 1
    for i in range(start_bar, n):
        if st_buy[i] and ema_f[i] > ema_s[i]:
            if adx_threshold is not None and adx_values[i] < adx_threshold: continue
            signals.append({'bar':i,'direction':'LONG','price':c[i],'atr':atr[i],
                           'adx':adx_values[i],'timestamp':df['timestamp'].iloc[i]})
        elif st_sell[i] and ema_f[i] < ema_s[i]:
            if adx_threshold is not None and adx_values[i] < adx_threshold: continue
            signals.append({'bar':i,'direction':'SHORT','price':c[i],'atr':atr[i],
                           'adx':adx_values[i],'timestamp':df['timestamp'].iloc[i]})
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

    # monthly breakdown
    df_t['month'] = pd.to_datetime(df_t['entry_time']).dt.to_period('M')
    monthly_pnl = df_t.groupby('month')['pnl'].sum()
    monthly_count = df_t.groupby('month').size()
    profitable_months = (monthly_pnl > 0).sum()
    total_months_traded = len(monthly_pnl)

    return {'label':label,'total':total,'wr':wr,'lc':len(longs),'sc':len(shorts),
            'lwr':lwr,'swr':swr,'pf':pf,'pnl':tp_val,'eq':10000+tp_val,'mdd':mdd,
            'ah':df_t['hold_bars'].mean(),'max_consec_loss':mc,
            'exits':df_t['exit_reason'].value_counts().to_dict(),
            'aw':aw,'al':al,'avg_adx':df_t['adx_at_entry'].mean(),
            'monthly_avg_trades': total / 24,
            'profitable_months': profitable_months,
            'total_months_traded': total_months_traded,
            'monthly_pnl': monthly_pnl,
            'monthly_count': monthly_count}


def plot_equity(eq_dict, output_dir, filename, title):
    fig, ax = plt.subplots(figsize=(16, 8))
    fig.patch.set_facecolor('#131722'); ax.set_facecolor('#131722')
    colors = ['#26a69a','#42a5f5','#ff7043','#ab47bc','#ffa726','#ef5350',
              '#66bb6a','#29b6f6','#ff8a65','#ce93d8','#78909c','#4db6ac']
    for i,(label,eq) in enumerate(eq_dict.items()):
        if not eq: continue
        ax.plot([e['timestamp'] for e in eq],[e['equity'] for e in eq],
                color=colors[i%len(colors)], linewidth=1.8, label=label, alpha=0.9)
    ax.axhline(y=10000, color='#787b86', linestyle='--', alpha=0.5)
    ax.set_title(title, color='#e6edf3', fontsize=14, fontweight='bold')
    ax.set_ylabel('Equity ($)', color='#e6edf3')
    ax.tick_params(colors='#787b86')
    ax.legend(loc='upper left', fontsize=7, facecolor='#1e222d', edgecolor='#363c4e', labelcolor='#e6edf3')
    ax.grid(True, alpha=0.1, color='#363c4e')
    for s in ax.spines.values(): s.set_color('#363c4e')
    fpath = os.path.join(output_dir, filename)
    fig.savefig(fpath, dpi=120, bbox_inches='tight', facecolor='#131722')
    plt.close(fig); return fpath


def plot_freq_vs_quality(results_list, output_dir):
    """Trade frequency vs quality scatter plot"""
    fig, axes = plt.subplots(1, 3, figsize=(20, 7))
    fig.patch.set_facecolor('#131722')

    valid = [r for r in results_list if r and r.get('pf', 0) > 0.5 and r.get('total', 0) >= 3]

    for ax in axes:
        ax.set_facecolor('#131722')
        ax.tick_params(colors='#787b86')
        ax.grid(True, alpha=0.1, color='#363c4e')
        for s in ax.spines.values(): s.set_color('#363c4e')

    # Color by timeframe
    tf_colors = {'1H': '#ff7043', '1.5H': '#ffa726', '2H': '#26a69a'}

    for r in valid:
        tf = r['label'].split(' ')[0]
        color = tf_colors.get(tf, '#42a5f5')
        trades_per_month = r['monthly_avg_trades']

        # Plot 1: Trades/month vs PF
        axes[0].scatter(trades_per_month, r['pf'], color=color, s=80, alpha=0.7, edgecolors='white', linewidth=0.5)

        # Plot 2: Trades/month vs MDD
        axes[1].scatter(trades_per_month, r['mdd'], color=color, s=80, alpha=0.7, edgecolors='white', linewidth=0.5)

        # Plot 3: Trades/month vs Monthly P&L
        monthly_pnl = r['pnl'] / 24
        axes[2].scatter(trades_per_month, monthly_pnl, color=color, s=80, alpha=0.7, edgecolors='white', linewidth=0.5)

    axes[0].set_xlabel('Trades/Month', color='#e6edf3')
    axes[0].set_ylabel('Profit Factor', color='#e6edf3')
    axes[0].set_title('Frequency vs Quality', color='#e6edf3', fontsize=12)
    axes[0].axhline(y=1.5, color='#26a69a', linestyle='--', alpha=0.5, label='PF=1.5')

    axes[1].set_xlabel('Trades/Month', color='#e6edf3')
    axes[1].set_ylabel('Max Drawdown %', color='#e6edf3')
    axes[1].set_title('Frequency vs Risk', color='#e6edf3', fontsize=12)
    axes[1].axhline(y=10, color='#ef5350', linestyle='--', alpha=0.5, label='MDD=10%')

    axes[2].set_xlabel('Trades/Month', color='#e6edf3')
    axes[2].set_ylabel('Monthly P&L ($)', color='#e6edf3')
    axes[2].set_title('Frequency vs Returns', color='#e6edf3', fontsize=12)

    # Legend for timeframes
    from matplotlib.lines import Line2D
    legend_elements = [Line2D([0],[0], marker='o', color='w', markerfacecolor=c, markersize=10, label=tf)
                       for tf, c in tf_colors.items()]
    axes[0].legend(handles=legend_elements, loc='upper right', fontsize=9,
                   facecolor='#1e222d', edgecolor='#363c4e', labelcolor='#e6edf3')

    fig.suptitle('Trade Frequency Optimization: Frequency vs Quality Trade-off',
                 color='#e6edf3', fontsize=14, fontweight='bold')
    plt.tight_layout()
    fpath = os.path.join(output_dir, 'freq_optimization_scatter.png')
    fig.savefig(fpath, dpi=120, bbox_inches='tight', facecolor='#131722')
    plt.close(fig)
    return fpath


def plot_risk_comparison(top_results, output_dir):
    """Risk 2% vs 5% comparison for top strategies"""
    fig, ax = plt.subplots(figsize=(16, 8))
    fig.patch.set_facecolor('#131722'); ax.set_facecolor('#131722')

    labels = [r['label'] for r in top_results[:8]]
    pnl_2pct = [r['pnl'] / 24 for r in top_results[:8]]  # monthly
    pnl_5pct = [r['pnl'] * 2.5 / 24 for r in top_results[:8]]
    mdd_2pct = [r['mdd'] for r in top_results[:8]]
    mdd_5pct = [r['mdd'] * 2.5 for r in top_results[:8]]

    x = np.arange(len(labels))
    width = 0.35

    bars1 = ax.bar(x - width/2, pnl_2pct, width, label='Risk 2% (monthly)', color='#42a5f5', alpha=0.8)
    bars2 = ax.bar(x + width/2, pnl_5pct, width, label='Risk 5% (monthly)', color='#26a69a', alpha=0.8)

    # Add MDD labels on bars
    for i, (b1, b2) in enumerate(zip(bars1, bars2)):
        ax.text(b1.get_x() + b1.get_width()/2, b1.get_height() + 5,
                f'DD:{mdd_2pct[i]:.1f}%', ha='center', va='bottom', color='#42a5f5', fontsize=7)
        ax.text(b2.get_x() + b2.get_width()/2, b2.get_height() + 5,
                f'DD:{mdd_5pct[i]:.1f}%', ha='center', va='bottom', color='#26a69a', fontsize=7)

    ax.set_ylabel('Monthly P&L ($)', color='#e6edf3')
    ax.set_title('Top Strategies: Risk 2% vs 5% Monthly Returns', color='#e6edf3', fontsize=13)
    ax.set_xticks(x)
    ax.set_xticklabels(labels, rotation=30, ha='right', fontsize=7, color='#e6edf3')
    ax.tick_params(colors='#787b86')
    ax.legend(fontsize=10, facecolor='#1e222d', edgecolor='#363c4e', labelcolor='#e6edf3')
    ax.grid(True, alpha=0.1, color='#363c4e', axis='y')
    for s in ax.spines.values(): s.set_color('#363c4e')

    fpath = os.path.join(output_dir, 'freq_risk_comparison.png')
    fig.savefig(fpath, dpi=120, bbox_inches='tight', facecolor='#131722')
    plt.close(fig)
    return fpath


def main():
    print("=" * 130)
    print("TRADE FREQUENCY OPTIMIZATION BACKTEST")
    print("Goal: More trades + Quality maintenance = Higher monthly returns")
    print("Period: 2024-2025 | Capital: $10,000 | Fee: 0.06%/side")
    print("=" * 130)

    df_m5 = pd.read_csv(DATA_M5)
    df_m5['timestamp'] = pd.to_datetime(df_m5['timestamp'])

    # ============================================================
    # Phase 1: Resample all timeframes
    # ============================================================
    print("\n[Phase 1] Resampling timeframes...")

    tf_data = {}
    for tf_name, freq, max_hold in [('1H', '1h', 120), ('1.5H', '90min', 80), ('2H', '2h', 60)]:
        df_tf = resample_ohlcv(df_m5, freq)
        mask = (df_tf['timestamp'] >= '2024-01-01') & (df_tf['timestamp'] <= '2025-12-31')
        df_tf = df_tf[mask].reset_index(drop=True)
        tf_data[tf_name] = {'df': df_tf, 'max_hold': max_hold}
        print(f"  {tf_name}: {len(df_tf):,} bars (max_hold={max_hold})")

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # ============================================================
    # Phase 2: Test all combinations
    # ============================================================
    print("\n[Phase 2] Testing TF x ADX x SL/TP combinations...")
    print(f"  Timeframes: 1H, 1.5H, 2H")
    print(f"  ADX thresholds: None, 15, 20")
    print(f"  SL/TP combos: 8 variations (RR 1:3 ~ 1:6)")

    # SL/TP combinations focusing on RR ratios 1:4, 1:5, 1:6 as requested
    sl_tp_configs = [
        # (sl_mult, tp_mult, rr_label)
        (2.0, 6.0, "RR1:3"),     # baseline - 2H champion
        (1.5, 6.0, "RR1:4"),     # tighter SL, same TP
        (2.0, 8.0, "RR1:4"),     # same SL, wider TP
        (1.5, 7.5, "RR1:5"),     # tight SL, 5x TP
        (2.0, 10.0, "RR1:5"),    # same SL, 5x TP
        (1.5, 9.0, "RR1:6"),     # tight SL, 6x TP
        (2.0, 12.0, "RR1:6"),    # same SL, 6x TP
        (1.0, 5.0, "RR1:5t"),    # very tight SL (more trades survive?)
    ]

    adx_thresholds = [None, 15, 20]

    all_results = []
    all_eq = {}
    total_configs = len(tf_data) * len(adx_thresholds) * len(sl_tp_configs)

    print(f"  Total configurations: {total_configs}\n")

    header = f"  {'Strategy':<45s} {'Sigs':>4s} {'Trds':>4s} {'WR%':>5s} {'PF':>5s} {'P&L':>9s} {'MDD%':>6s} {'Strk':>4s} {'T/Mo':>5s} {'Mo$':>6s} {'AvgH':>5s}"
    print(header)
    print("  " + "-" * 120)

    for tf_name, tf_info in tf_data.items():
        df_tf = tf_info['df']
        max_hold = tf_info['max_hold']

        for adx_th in adx_thresholds:
            for sl_m, tp_m, rr_label in sl_tp_configs:
                adx_label = f"ADX>{adx_th}" if adx_th else "NoADX"
                label = f"{tf_name} {adx_label} SL{sl_m}/TP{tp_m} ({rr_label})"

                sigs, _ = generate_signals(df_tf, 10, 3.0, 20, 50,
                                           adx_period=14, adx_threshold=adx_th)
                trades, eq, _ = backtest_fixed(df_tf, sigs, sl_m=sl_m, tp_m=tp_m,
                                               max_hold=max_hold, risk=0.02)
                s = analyze(trades, label)

                if s:
                    all_results.append(s)
                    all_eq[label] = eq
                    pf_str = f"{s['pf']:>5.2f}" if s['pf'] < 100 else "  INF"
                    monthly = s['pnl'] / 24
                    t_per_mo = s['total'] / 24
                    print(f"  {label:<45s} {len(sigs):>4d} {s['total']:>4d} {s['wr']:>4.1f}% {pf_str} "
                          f"${s['pnl']:>8,.0f} {s['mdd']:>5.1f}% {s['max_consec_loss']:>4d} "
                          f"{t_per_mo:>5.1f} ${monthly:>5.0f} {s['ah']:>4.0f}b")
                else:
                    print(f"  {label:<45s} {len(sigs):>4d}  -> No trades")

    # ============================================================
    # Phase 3: Rankings
    # ============================================================
    print("\n" + "=" * 130)
    print("PHASE 3: RANKINGS")
    print("=" * 130)

    # Filter: PF > 1.0, trades >= 5
    valid = [r for r in all_results if r.get('pf', 0) > 1.0 and r.get('total', 0) >= 5]

    # --- Rank by Monthly P&L (risk 2%) ---
    print("\n--- RANK BY MONTHLY P&L (Risk 2%) ---")
    print(f"  {'#':>3s} {'Strategy':<45s} {'Trds':>4s} {'T/Mo':>5s} {'PF':>5s} {'Mo$':>6s} {'MDD%':>6s} {'WR%':>5s} {'Strk':>4s}")
    print("  " + "-" * 95)

    by_pnl = sorted(valid, key=lambda x: x['pnl'], reverse=True)
    for i, s in enumerate(by_pnl[:15], 1):
        monthly = s['pnl'] / 24
        t_per_mo = s['total'] / 24
        marker = " ** " if s['pf'] >= 1.5 and s['mdd'] < 15 else "    "
        print(f"  {marker}{i:>2d} {s['label']:<45s} {s['total']:>4d} {t_per_mo:>5.1f} {s['pf']:>5.2f} "
              f"${monthly:>5.0f} {s['mdd']:>5.1f}% {s['wr']:>4.1f}% {s['max_consec_loss']:>4d}")

    # --- Rank by PF (quality) ---
    print("\n--- RANK BY PROFIT FACTOR (Quality) ---")
    print(f"  {'#':>3s} {'Strategy':<45s} {'Trds':>4s} {'T/Mo':>5s} {'PF':>5s} {'Mo$':>6s} {'MDD%':>6s} {'WR%':>5s}")
    print("  " + "-" * 90)

    by_pf = sorted(valid, key=lambda x: x['pf'], reverse=True)
    for i, s in enumerate(by_pf[:15], 1):
        monthly = s['pnl'] / 24
        t_per_mo = s['total'] / 24
        print(f"  {i:>5d} {s['label']:<45s} {s['total']:>4d} {t_per_mo:>5.1f} {s['pf']:>5.2f} "
              f"${monthly:>5.0f} {s['mdd']:>5.1f}% {s['wr']:>4.1f}%")

    # --- Rank by EFFICIENCY SCORE ---
    # Score = (Monthly PnL) / (MDD) * sqrt(trades/month)
    # Higher = better balance of returns, risk, and frequency
    print("\n--- RANK BY EFFICIENCY SCORE = (Monthly_PnL / MDD) * sqrt(Trades/Month) ---")
    print(f"  {'#':>3s} {'Strategy':<45s} {'Score':>7s} {'Trds':>4s} {'T/Mo':>5s} {'PF':>5s} {'Mo$':>6s} {'MDD%':>6s} {'5%Mo$':>7s} {'5%MDD':>6s}")
    print("  " + "-" * 115)

    for r in valid:
        monthly = r['pnl'] / 24
        t_per_mo = r['total'] / 24
        if r['mdd'] > 0 and t_per_mo > 0:
            r['eff_score'] = (monthly / r['mdd']) * np.sqrt(t_per_mo)
        else:
            r['eff_score'] = 0

    by_eff = sorted(valid, key=lambda x: x.get('eff_score', 0), reverse=True)
    for i, s in enumerate(by_eff[:15], 1):
        monthly = s['pnl'] / 24
        t_per_mo = s['total'] / 24
        monthly_5pct = monthly * 2.5
        mdd_5pct = s['mdd'] * 2.5
        marker = " >> " if i <= 5 else "    "
        print(f"  {marker}{i:>2d} {s['label']:<45s} {s['eff_score']:>7.2f} {s['total']:>4d} {t_per_mo:>5.1f} {s['pf']:>5.2f} "
              f"${monthly:>5.0f} {s['mdd']:>5.1f}% ${monthly_5pct:>6.0f} {mdd_5pct:>5.1f}%")

    # ============================================================
    # Phase 4: Risk scaling comparison
    # ============================================================
    print("\n" + "=" * 130)
    print("PHASE 4: RISK SCALING - Top 5 Strategies")
    print("=" * 130)

    top5 = by_eff[:5]
    for s in top5:
        monthly_base = s['pnl'] / 24
        print(f"\n  {s['label']}")
        print(f"  {'Risk%':>8s} {'Monthly$':>10s} {'Annual$':>10s} {'Annual%':>8s} {'MDD':>7s} {'Trades':>7s}")
        print(f"  {'-'*55}")
        for risk_pct in [2, 3, 5, 7, 10]:
            mult = risk_pct / 2.0
            mo = monthly_base * mult
            annual = mo * 12
            annual_pct = annual / 10000 * 100
            mdd = s['mdd'] * mult
            print(f"  {risk_pct:>7d}% ${mo:>9.0f} ${annual:>9.0f} {annual_pct:>7.1f}% {mdd:>6.1f}% {s['total']:>7d}")

    # ============================================================
    # Phase 5: Target analysis - how to reach 20%+ monthly
    # ============================================================
    print("\n" + "=" * 130)
    print("PHASE 5: TARGET ANALYSIS - How to reach ~20% monthly return")
    print("=" * 130)
    print(f"  Target: ~$2,000/month on $10,000 = 20% monthly")
    print(f"  Constraint: MDD < 20%\n")

    for s in by_eff[:10]:
        monthly_2pct = s['pnl'] / 24
        if monthly_2pct <= 0: continue

        # What risk% needed for $2000/month?
        needed_mult = 2000 / monthly_2pct
        needed_risk = 2.0 * needed_mult
        resulting_mdd = s['mdd'] * needed_mult

        feasible = "OK" if resulting_mdd < 20 else "HIGH MDD" if resulting_mdd < 35 else "DANGEROUS"

        print(f"  {s['label']:<45s} Need Risk:{needed_risk:>5.1f}%  MDD:{resulting_mdd:>5.1f}%  [{feasible}]")

    # ============================================================
    # Charts
    # ============================================================
    print("\n\n[Charts] Generating...")

    # Chart 1: Frequency vs Quality scatter
    p1 = plot_freq_vs_quality(all_results, OUTPUT_DIR)
    print(f"  Scatter plot: {p1}")

    # Chart 2: Risk comparison bar chart
    p2 = plot_risk_comparison(by_eff, OUTPUT_DIR)
    print(f"  Risk comparison: {p2}")

    # Chart 3: Top equity curves
    top_eq = {}
    for s in by_eff[:6]:
        if s['label'] in all_eq:
            top_eq[s['label']] = all_eq[s['label']]
    # Always include 2H champion
    champ_key = '2H ADX>20 SL2.0/TP6.0 (RR1:3)'
    if champ_key in all_eq:
        top_eq['2H ADX>20 SL2/TP6 (CHAMPION)'] = all_eq[champ_key]

    p3 = plot_equity(top_eq, OUTPUT_DIR, 'freq_top_equity.png',
                     'Top Strategies by Efficiency Score (2024-2025, Risk 2%)')
    print(f"  Top equity curves: {p3}")

    print("\n" + "=" * 130)
    print("OPTIMIZATION COMPLETE")
    print("=" * 130)


if __name__ == '__main__':
    main()
