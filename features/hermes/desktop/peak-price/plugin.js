/**
 * DeepSeek peak/off-peak pricing in the Hermes desktop UI.
 *
 *   statusBar.right  — small coloured pill, always visible
 *   hover / focus    — detail card floats above it (no permanent pane)
 *   notifications    — in-app toast + native OS notification on every flip
 *
 * Peak (2x): Mon–Fri 01:00–04:00 and 06:00–10:00 UTC. Everything else is half
 * price, weekends included. Plain ESM, loaded uncompiled — jsx() calls.
 */

import { cn, haptic, host } from '@hermes/plugin-sdk'
import { jsx, jsxs } from 'react/jsx-runtime'
import { useEffect, useRef, useState } from 'react'

const ID = 'peak-price'
const WINDOWS = [
  [1, 4],
  [6, 10]
]

// Theme-aware colours: reskins with the app instead of fighting it.
const GREEN = 'var(--ui-green)'
const RED = 'var(--ui-red)'
const GREEN_EDGE = 'color-mix(in oklab, var(--ui-green) 45%, transparent)'
const RED_EDGE = 'color-mix(in oklab, var(--ui-red) 50%, transparent)'
const tint = (v, pct) => `color-mix(in oklab, ${v} ${pct}%, transparent)`

/* ---------- the schedule ---------- */

function isPeak(d) {
  const day = d.getUTCDay()
  if (day === 0 || day === 6) return false
  const h = d.getUTCHours() + d.getUTCMinutes() / 60
  return WINDOWS.some(([a, b]) => h >= a && h < b)
}

function nextFlip(from) {
  const cur = isPeak(from)
  const t = new Date(from)
  t.setSeconds(0, 0)
  for (let i = 0; i < 60 * 24 * 8; i++) {
    t.setMinutes(t.getMinutes() + 1)
    if (isPeak(t) !== cur) return t
  }
  return null
}

const hm = d =>
  d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
const wd = d => d.toLocaleDateString([], { weekday: 'short' })

function human(ms) {
  const mins = Math.max(0, Math.round(ms / 60000))
  const h = Math.floor(mins / 60)
  const m = mins % 60
  return (h ? h + 'h ' : '') + String(m).padStart(2, '0') + 'm'
}

function midnight(d) {
  const m = new Date(d)
  m.setHours(0, 0, 0, 0)
  return m
}

/** Calendar-day arithmetic — ms arithmetic breaks across DST changes. */
function addDays(d, n) {
  const out = new Date(d)
  out.setDate(out.getDate() + n)
  return out
}

/** Walk a local day in 5-min steps, returning [startIdx, endIdx] peak runs. */
function peakRuns(dayStart) {
  const step = 5
  const total = 1440 / step
  const out = []
  let run = null
  for (let i = 0; i < total; i++) {
    const p = isPeak(new Date(dayStart.getTime() + i * step * 60000))
    if (p && run === null) run = i
    if (!p && run !== null) {
      out.push([run, i])
      run = null
    }
  }
  if (run !== null) out.push([run, total])
  return { runs: out, total, step }
}

function segments(dayStart) {
  const { runs, total } = peakRuns(dayStart)
  return runs.map(([a, b]) => ({ left: (a / total) * 100, width: ((b - a) / total) * 100 }))
}

function windowLabels(dayStart) {
  const { runs, step } = peakRuns(dayStart)
  const at = i => hm(new Date(dayStart.getTime() + i * step * 60000))
  return runs.map(([a, b]) => at(a) + '–' + at(b))
}

function statusLine(now) {
  const peak = isPeak(now)
  const flip = nextFlip(now)
  const when = flip ? `${wd(flip)} ${hm(flip)} (in ${human(flip - now)})` : '?'
  return peak
    ? `Peak pricing: 2× rates ($0.30 in / $1.20 out per 1M). Half price ${when}.`
    : `Off-peak: half price ($0.15 in / $0.60 out per 1M). Peak ${when}.`
}

/* ---------- shared bits ---------- */

function pillStyle(peak) {
  return {
    color: peak ? RED : GREEN,
    background: tint(peak ? RED : GREEN, 16),
    border: `1px solid ${peak ? RED_EDGE : GREEN_EDGE}`,
    boxShadow: `0 0 10px ${tint(peak ? RED : GREEN, 20)}`
  }
}

function Dot({ on }) {
  return jsx('span', {
    'aria-hidden': true,
    style: {
      width: 8,
      height: 8,
      borderRadius: 999,
      display: 'inline-block',
      background: on ? RED : GREEN,
      boxShadow: `0 0 8px ${on ? RED : GREEN}`
    }
  })
}

const cardStyle = {
  border: '1px solid var(--ui-stroke-secondary)',
  borderRadius: 10,
  padding: '8px 10px'
}

function RateCard({ label, value, on, edge, colour }) {
  return jsxs('div', {
    style: {
      ...cardStyle,
      flex: 1,
      opacity: on ? 1 : 0.4,
      borderColor: on ? edge : undefined
    },
    children: [
      jsx('div', { className: 'text-(--ui-text-tertiary)', children: label }),
      jsx('div', {
        className: 'tabular-nums',
        style: { color: on ? colour : undefined, fontWeight: 600 },
        children: value
      })
    ]
  })
}

/* ---------- the floating detail card ---------- */

function PeakCard({ ctx, style, onMouseEnter, onMouseLeave }) {
  const [now, setNow] = useState(() => new Date())
  const [bal, setBal] = useState(null)
  const [balErr, setBalErr] = useState(false)

  useEffect(() => {
    const t = setInterval(() => setNow(new Date()), 1000)
    return () => clearInterval(t)
  }, [])

  // Balance comes from the plugin backend, which reads the same script the
  // cron job runs. Degrades to a dash when the backend half is off.
  useEffect(() => {
    if (!ctx || !ctx.rest) return
    let alive = true
    const load = async () => {
      try {
        const r = await ctx.rest('/balance')
        if (!alive) return
        if (r && r.ok) {
          setBal(r)
          setBalErr(false)
        } else {
          setBalErr(true)
        }
      } catch (e) {
        if (alive) setBalErr(true)
      }
    }
    load()
    const t = setInterval(load, 60000)
    return () => {
      alive = false
      clearInterval(t)
    }
  }, [ctx])

  const peak = isPeak(now)
  const flip = nextFlip(now)
  const money = v => '$' + Number(v).toFixed(2)
  const balColor = bal && bal.usd < 1 ? RED : GREEN
  const balNote = bal
    ? [
        bal.stale ? 'stale' : null,
        bal.days_left != null ? `≈ ${bal.days_left} d left` : null,
        bal.spent_24h != null ? `${money(bal.spent_24h)} in 24h` : 'no history yet'
      ]
        .filter(Boolean)
        .join(' · ')
    : ''
  const start = midnight(now)
  const dayPct = ((now - start) / 86400000) * 100

  return jsxs('div', {
    style: {
      position: 'fixed',
      zIndex: 2147483000,
      background: 'var(--ui-bg-elevated)',
      border: '1px solid var(--ui-stroke-secondary)',
      borderRadius: 12,
      boxShadow: '0 12px 32px rgba(0,0,0,.38)',
      padding: 12,
      maxHeight: 'min(70vh, 540px)',
      overflow: 'auto',
      ...style
    },
    className: 'flex flex-col gap-3 text-xs',
    onMouseEnter,
    onMouseLeave,
    children: [
      jsxs('div', {
        className: 'flex items-center justify-between gap-2',
        children: [
          jsxs('span', {
            className:
              'inline-flex items-center gap-1.5 rounded-full px-2 py-1 text-[0.6875rem] font-semibold',
            style: pillStyle(peak),
            children: [
              jsx(Dot, { on: peak }),
              jsx('span', { children: peak ? 'PEAK 2×' : 'OFF-PEAK ½' })
            ]
          }),
          jsx('span', {
            className: 'tabular-nums text-(--ui-text-tertiary)',
            children: hm(now)
          })
        ]
      }),

      jsxs('div', {
        className: 'flex flex-col gap-1',
        children: [
          jsx('div', {
            style: {
              position: 'relative',
              height: 10,
              borderRadius: 999,
              overflow: 'hidden',
              background: 'var(--ui-bg-tertiary)',
              border: '1px solid var(--ui-stroke-secondary)'
            },
            children: [
              ...segments(start).map((s, i) =>
                jsx('div', {
                  key: 'seg' + i,
                  style: {
                    position: 'absolute',
                    top: 0,
                    bottom: 0,
                    left: s.left + '%',
                    width: s.width + '%',
                    background: `linear-gradient(180deg, var(--ui-red), color-mix(in oklab, var(--ui-red) 70%, black))`
                  }
                })
              ),
              jsx('div', {
                style: {
                  position: 'absolute',
                  top: -2,
                  bottom: -2,
                  left: dayPct + '%',
                  width: 2,
                  background: 'var(--ui-text-secondary)'
                }
              })
            ]
          }),
          jsx('div', {
            className: 'flex justify-between text-[0.625rem] text-(--ui-text-quaternary)',
            children: ['00', '06', '12', '18', '24'].map(t => jsx('span', { key: t, children: t }))
          })
        ]
      }),

      jsx('div', {
        style: cardStyle,
        children: jsx('div', {
          children: flip
            ? `${peak ? 'Half price' : 'Double price'} ${peak ? 'returns' : 'starts'} in ${human(flip - now)} · ${wd(flip)} ${hm(flip)}`
            : '…'
        })
      }),

      jsxs('div', {
        style: {
          ...cardStyle,
          display: 'flex',
          alignItems: 'baseline',
          justifyContent: 'space-between',
          gap: 8,
          borderColor: balErr ? undefined : tint(balColor, 45)
        },
        children: [
          jsx('span', { className: 'text-(--ui-text-tertiary)', children: 'Credit left' }),
          jsxs('span', {
            className: 'flex items-baseline gap-1.5',
            children: [
              jsx('span', {
                className: 'tabular-nums',
                style: {
                  color: balErr ? undefined : balColor,
                  fontWeight: 700,
                  fontSize: 15
                },
                children: balErr ? '—' : bal ? money(bal.usd) : '…'
              }),
              jsx('span', {
                className: 'text-[0.625rem] text-(--ui-text-quaternary)',
                children: balErr ? 'backend off' : balNote
              })
            ]
          })
        ]
      }),

      jsxs('div', {
        className: 'flex gap-2',
        children: [
          jsx(RateCard, {
            label: 'Off-peak',
            value: '$0.15 / $0.60',
            on: !peak,
            edge: GREEN_EDGE,
            colour: GREEN
          }),
          jsx(RateCard, {
            label: 'Peak',
            value: '$0.30 / $1.20',
            on: peak,
            edge: RED_EDGE,
            colour: RED
          })
        ]
      }),

      jsxs('div', {
        className: 'flex flex-col gap-1',
        children: [
          jsx('div', {
            className: 'text-[0.625rem] uppercase tracking-wider text-(--ui-text-quaternary)',
            children: 'Next 7 days'
          }),
          ...[0, 1, 2, 3, 4, 5, 6].map(offset => {
            const d = addDays(start, offset)
            const labels = windowLabels(d)
            return jsxs(
              'div',
              {
                className: 'flex items-baseline justify-between gap-2',
                children: [
                  jsx('span', { className: 'text-(--ui-text-tertiary)', children: wd(d) }),
                  jsx('span', {
                    className: 'tabular-nums',
                    style: { color: labels.length ? RED : GREEN },
                    children: labels.length ? labels.join(', ') : 'half price'
                  })
                ]
              },
              'd' + offset
            )
          })
        ]
      })
    ]
  })
}

/* ---------- status bar pill + hover ---------- */

const CARD_W = 320

function PeakChip({ ctx }) {
  const [now, setNow] = useState(() => new Date())
  const [anchor, setAnchor] = useState(null)
  const btn = useRef(null)
  const closer = useRef(null)

  useEffect(() => {
    const t = setInterval(() => setNow(new Date()), 1000)
    return () => clearInterval(t)
  }, [])

  // A stale card floating in the wrong place is worse than none.
  useEffect(() => {
    if (!anchor) return
    const close = () => setAnchor(null)
    window.addEventListener('resize', close)
    window.addEventListener('scroll', close, true)
    return () => {
      window.removeEventListener('resize', close)
      window.removeEventListener('scroll', close, true)
    }
  }, [anchor])

  useEffect(() => () => clearTimeout(closer.current), [])

  const open = () => {
    clearTimeout(closer.current)
    const r = btn.current && btn.current.getBoundingClientRect()
    if (r) setAnchor({ top: r.top, right: r.right })
  }

  const scheduleClose = () => {
    clearTimeout(closer.current)
    closer.current = setTimeout(() => setAnchor(null), 240)
  }

  const closeNow = () => {
    clearTimeout(closer.current)
    setAnchor(null)
  }

  const peak = isPeak(now)

  return jsxs('span', {
    className: 'inline-flex h-full items-center',
    onMouseEnter: open,
    onMouseLeave: scheduleClose,
    children: [
      jsxs('button', {
        ref: btn,
        type: 'button',
        'aria-expanded': anchor ? 'true' : 'false',
        className: cn(
          'inline-flex h-full items-center gap-1 self-center rounded-full px-2',
          'text-[0.6875rem] font-semibold transition-colors'
        ),
        style: pillStyle(peak),
        onFocus: open,
        onBlur: scheduleClose,
        onKeyDown: e => {
          if (e.key === 'Escape') closeNow()
        },
        onClick: () => {
          haptic('tap')
          if (anchor) closeNow()
          else open()
        },
        children: [
          jsx(Dot, { on: peak }),
          jsx('span', { children: peak ? 'PEAK 2×' : 'OFF-PEAK ½' })
        ]
      }),
      anchor &&
        jsx(PeakCard, {
          ctx,
          style: {
            width: CARD_W,
            bottom: Math.max(8, window.innerHeight - anchor.top + 8) + 'px',
            left:
              Math.max(
                8,
                Math.min(anchor.right - CARD_W, window.innerWidth - CARD_W - 8)
              ) + 'px'
          },
          onMouseEnter: open,
          onMouseLeave: scheduleClose
        })
    ]
  })
}

/* ---------- plugin ---------- */

export default {
  id: ID,
  name: 'Peak price',
  register(ctx) {
    ctx.register({
      id: 'chip',
      area: 'statusBar.right',
      order: 140,
      render: () => jsx(PeakChip, { ctx })
    })

    // Notify on every flip: in-app toast always, native OS notification when away.
    if (globalThis.__peakPriceTimer) clearInterval(globalThis.__peakPriceTimer)
    let last = isPeak(new Date())
    globalThis.__peakPriceTimer = setInterval(() => {
      const now = new Date()
      const flag = isPeak(now)
      if (flag === last) return
      last = flag
      const body = statusLine(now)
      host.notify({ kind: flag ? 'warning' : 'success', message: body })
      try {
        ctx.os.notify({
          title: flag ? 'Peak pricing just started' : 'Off-peak pricing is back',
          body,
          silent: false
        })
      } catch (e) {
        // native notifications are best-effort
      }
    }, 20000)
  }
}
