// Faithful, live mockups of the Mac and iPhone apps. Sizes are in real points
// (the Mac bubble is 300pt wide, the iPhone 393pt) and scaled down to fit.
import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import Ring from './Ring.jsx';
import { formatTime } from './timer.js';
import * as I from './Icons.jsx';

// ---- Scale a fixed-size design to its container --------------------------------
export function Scaled({ width, height, children, className = '' }) {
  const outer = useRef(null);
  const [scale, setScale] = useState(1);
  useLayoutEffect(() => {
    const el = outer.current;
    if (!el) return;
    const update = () => setScale(Math.min(1, el.clientWidth / width));
    update();
    const ro = new ResizeObserver(update);
    ro.observe(el);
    return () => ro.disconnect();
  }, [width]);
  return (
    <div ref={outer} className={`scaled ${className}`} style={{ height: height * scale }}>
      <div className="scaled-inner" style={{ width, height, transform: `scale(${scale})` }}>
        {children}
      </div>
    </div>
  );
}

// ---- The ring with the app's center: cycle dots, time, action ------------------
const appFraction = (timer) => (timer.status === 'idle' ? 1 : timer.remaining / timer.total);

function subtitleFor(timer) {
  if (timer.status === 'idle') return ['play', 'Start'];
  if (timer.status === 'paused') return ['play', 'Resume'];
  return [null, 'Focus'];
}

export function AppRing({
  timer,
  spectrum,
  size,
  lineWidth,
  fraction,
  time,
  subtitle,
  symbol,
  onTap,
  children,
  className = '',
  ...rest
}) {
  const [sym, label] = subtitle ? [symbol ?? null, subtitle] : subtitleFor(timer);
  const Sym = sym === 'play' ? I.Play : sym === 'pause' ? I.Pause : null;
  return (
    <Ring
      fraction={fraction ?? appFraction(timer)}
      spectrum={spectrum}
      animate={timer.status === 'running'}
      width={(lineWidth * 200) / size}
      className={`app-ring ${className}`}
      {...rest}
    >
      <button
        className="app-ring-center"
        onClick={onTap}
        tabIndex={onTap ? 0 : -1}
        aria-label={label}
        style={{ '--s': `${size}px` }}
      >
        <span className="cycle-dots" aria-hidden="true">
          <i className="on" />
          <i />
          <i />
          <i />
        </span>
        <span className="app-ring-time tabular">{time ?? formatTime(timer.remaining)}</span>
        <span className="app-ring-sub">
          {Sym && <Sym size={Math.max(8, size * 0.04)} />}
          {label}
        </span>
        {children}
      </button>
    </Ring>
  );
}

// ---- Pills ----------------------------------------------------------------------
function Pill({ children, prominent, square, className = '' }) {
  return (
    <span
      className={`pill ${prominent ? 'pill--prominent' : ''} ${square ? 'pill--square' : ''} ${className}`}
    >
      {children}
    </span>
  );
}

// ---- macOS: the glass bubble -------------------------------------------------------
const BUBBLE_W = 300;
const BUBBLE_H = 387;

function bubblePath(w, h, arrowX, arrowH = 11, arrowW = 34, r = 28) {
  const half = arrowW / 2;
  const x = Math.min(Math.max(arrowX, r + half), w - r - half);
  const t = arrowH;
  return [
    `M ${r} ${t}`,
    `L ${x - half} ${t}`,
    `C ${x - half * 0.45} ${t} ${x - half * 0.32} 0 ${x} 0`,
    `C ${x + half * 0.32} 0 ${x + half * 0.45} ${t} ${x + half} ${t}`,
    `L ${w - r} ${t}`,
    `A ${r} ${r} 0 0 1 ${w} ${t + r}`,
    `L ${w} ${h - r}`,
    `A ${r} ${r} 0 0 1 ${w - r} ${h}`,
    `L ${r} ${h}`,
    `A ${r} ${r} 0 0 1 0 ${h - r}`,
    `L 0 ${t + r}`,
    `A ${r} ${r} 0 0 1 ${r} ${t}`,
    'Z',
  ].join(' ');
}

function BubbleTimer({ timer, spectrum }) {
  const live = timer.status !== 'idle';
  return (
    <>
      <div className="mac-row">
        <Pill>
          <I.CircleDashed size={14} />
          Focus
          <I.ChevronUpDown size={8} className="dim-icon" />
        </Pill>
        <span className="spacer" />
        <Pill square>
          <I.LaptopPhone size={16} />
        </Pill>
      </div>
      <div className="mac-ring">
        <AppRing timer={timer} spectrum={spectrum} size={204} lineWidth={5} onTap={timer.toggle} />
      </div>
      <div className="mac-field">
        <span className="mac-chip">
          <I.Folder size={12} />
        </span>
        <span>Write the intro chapter</span>
      </div>
      <div className="mac-row">
        <Pill>
          {live ? <I.Plus size={12} /> : <I.Timer size={14} />}
          <span className="tabular">{live ? 'Time' : `${timer.minutes} min`}</span>
        </Pill>
        <Pill square>
          <I.TextBubble size={15} />
        </Pill>
        {live && (
          <Pill square>
            <I.Reset size={15} />
          </Pill>
        )}
        <span className="spacer" />
        <Pill square>
          <I.ChartBar size={15} />
        </Pill>
        <Pill square>
          <I.Ellipsis size={15} />
        </Pill>
      </div>
    </>
  );
}

const MEMBERS = [
  ['M', 'Mira’s MacBook', 'Here'],
  ['J', 'Jonas', 'Here'],
  ['L', 'Lena’s iPhone', 'Away'],
];

function BubbleLink() {
  return (
    <>
      <div className="mac-row">
        <span className="mac-title">Your group</span>
        <span className="spacer" />
        <Pill square>
          <svg
            width="15"
            height="15"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2.4"
            strokeLinecap="round"
            strokeLinejoin="round"
            aria-hidden="true"
          >
            <path d="M5 12.5l4.5 4.5L19 7.5" />
          </svg>
        </Pill>
      </div>
      <div className="link-card">
        <span className="link-caption">Group code</span>
        <span className="link-code-text">KQ7 M2P</span>
        <div className="mac-row mac-row--center">
          <Pill>
            <I.Copy size={13} /> Copy Code
          </Pill>
          <Pill>
            <I.Leave size={13} /> Leave
          </Pill>
        </div>
        <ul className="members">
          <li>
            <span className="member-avatar">Y</span>
            <span>Your Mac</span>
            <span className="member-state">You</span>
          </li>
          {MEMBERS.map(([a, name, state]) => (
            <li key={name}>
              <span className="member-avatar">{a}</span>
              <span>{name}</span>
              <span className="member-state">{state}</span>
            </li>
          ))}
        </ul>
      </div>
    </>
  );
}

export function MacBubble({ timer, spectrum, mode = 'timer', arrowX = BUBBLE_W / 2 }) {
  const d = bubblePath(BUBBLE_W, BUBBLE_H, arrowX);
  // A mask (unlike clip-path) also trims the backdrop blur to the bubble's shape.
  const mask = `url("data:image/svg+xml,${encodeURIComponent(
    `<svg xmlns='http://www.w3.org/2000/svg' width='${BUBBLE_W}' height='${BUBBLE_H}'><path d='${d}'/></svg>`
  )}")`;
  return (
    <div className="mac-bubble-wrap" style={{ width: BUBBLE_W, height: BUBBLE_H }}>
      <svg className="mac-bubble-shadow" width={BUBBLE_W} height={BUBBLE_H} aria-hidden="true">
        <path d={d} />
      </svg>
      <div className="mac-bubble" style={{ WebkitMaskImage: mask, maskImage: mask }}>
        {mode === 'link' ? <BubbleLink /> : <BubbleTimer timer={timer} spectrum={spectrum} />}
      </div>
      <svg className="mac-bubble-rim" width={BUBBLE_W} height={BUBBLE_H} aria-hidden="true">
        <path d={d} />
      </svg>
    </div>
  );
}

// ---- macOS: menu bar + desktop ----------------------------------------------------------
function useClock() {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const id = setInterval(() => setNow(new Date()), 15_000);
    return () => clearInterval(id);
  }, []);
  return now;
}

export function useNarrow(query = '(max-width: 640px)') {
  const [narrow, setNarrow] = useState(() => window.matchMedia(query).matches);
  useEffect(() => {
    const mq = window.matchMedia(query);
    const on = () => setNarrow(mq.matches);
    mq.addEventListener('change', on);
    return () => mq.removeEventListener('change', on);
  }, [query]);
  return narrow;
}

export function MacDesktop({ timer, spectrum, mode = 'timer', width: wide = 880, height = 470 }) {
  const now = useClock();
  const narrow = useNarrow();
  const width = narrow ? 420 : wide;
  const compact = width < 600;
  const desk = useRef(null);
  const item = useRef(null);
  const [pos, setPos] = useState({ left: width - 420, arrowX: 200 });

  useLayoutEffect(() => {
    if (!desk.current || !item.current) return;
    const d = desk.current.getBoundingClientRect();
    const r = item.current.getBoundingClientRect();
    const scale = d.width / width || 1;
    const center = (r.left - d.left + r.width / 2) / scale;
    const left = Math.min(Math.max(center - BUBBLE_W / 2, 12), width - BUBBLE_W - 12);
    setPos({ left, arrowX: center - left });
  }, [width, timer.status, mode]);

  const live = timer.status !== 'idle';
  const date = now.toLocaleDateString('en-GB', {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
  });
  const time = now.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });

  return (
    <Scaled width={width} height={height} className="mac-scaled">
      <div className="desktop" ref={desk} style={{ width, height }}>
        <div className="menubar">
          <div className="menubar-left">
            <b>Finder</b>
            <span>File</span>
            <span>Edit</span>
            {!compact && (
              <>
                <span>View</span>
                <span>Go</span>
                <span>Window</span>
                <span>Help</span>
              </>
            )}
          </div>
          <div className="menubar-right">
            <span className="menubar-item is-open" ref={item}>
              <Ring
                fraction={live ? timer.remaining / timer.total : 1}
                spectrum={spectrum}
                animate={timer.status === 'running'}
                width={16}
                className="ring--menubar"
              />
              <span className="tabular">{formatTime(timer.remaining)}</span>
            </span>
            <I.Battery size={19} />
            <I.Wifi size={15} />
            {!compact && <I.Search size={14} />}
            <I.Toggles size={15} />
            <span className="tabular">{compact ? time : `${date} ${time}`}</span>
          </div>
        </div>
        <div className="desktop-bubble" style={{ left: pos.left }}>
          <MacBubble timer={timer} spectrum={spectrum} mode={mode} arrowX={pos.arrowX} />
        </div>
      </div>
    </Scaled>
  );
}

// ---- iPhone ---------------------------------------------------------------------------
const PHONE_W = 393;
const PHONE_H = 852;

function StatusBar({ light }) {
  return (
    <div className={`ios-status ${light ? 'is-light' : ''}`}>
      <span className="tabular">9:41</span>
      <span className="ios-status-right">
        <I.Signal size={17} />
        <I.Wifi size={16} />
        <I.Battery size={24} />
      </span>
    </div>
  );
}

export function IPhone({ children, light, className = '' }) {
  return (
    <div className={`iphone ${className}`} style={{ width: PHONE_W, height: PHONE_H }}>
      <div className="iphone-screen">
        <StatusBar light={light} />
        <div className="iphone-island" />
        {children}
        <div className={`iphone-home ${light ? 'is-light' : ''}`} />
      </div>
    </div>
  );
}

export function ScaledPhone({ children, light, width = 300 }) {
  return (
    <div className="phone-slot" style={{ maxWidth: width }}>
      <Scaled width={PHONE_W + 24} height={PHONE_H + 24}>
        <div style={{ padding: 12 }}>
          <IPhone light={light}>{children}</IPhone>
        </div>
      </Scaled>
    </div>
  );
}

export function IOSTimer({ timer, spectrum, subtitle, symbol }) {
  const live = timer.status !== 'idle';
  return (
    <div className="ios-app">
      <div className="ios-top">
        <Pill>
          <I.CircleDashed size={18} />
          Focus
          <I.ChevronUpDown size={10} className="dim-icon" />
        </Pill>
        <span className="spacer" />
        {live ? (
          <>
            <Pill square>
              <I.Plus size={17} />
            </Pill>
            <Pill>
              <I.Reset size={17} /> Reset
            </Pill>
          </>
        ) : (
          <Pill>
            <I.Timer size={18} />
            <span className="tabular">{timer.minutes} min</span>
          </Pill>
        )}
      </div>
      <div className="ios-ring">
        <AppRing
          timer={timer}
          spectrum={spectrum}
          size={330}
          lineWidth={6}
          onTap={timer.toggle}
          subtitle={subtitle}
          symbol={symbol}
        />
      </div>
      <TabBar selected="Timer" />
    </div>
  );
}

function TabBar({ selected }) {
  const tabs = [
    ['Link', I.People],
    ['Timer', I.Timer],
    ['Analytics', I.ChartBar],
    ['Settings', I.Gear],
  ];
  return (
    <div className="ios-tabbar">
      {tabs.map(([name, Icon]) => (
        <span key={name} className={name === selected ? 'is-on' : ''}>
          <Icon size={24} />
          {name}
        </span>
      ))}
    </div>
  );
}

export function LockScreen({ timer }) {
  const paused = timer.status === 'paused';
  const live = timer.status !== 'idle';
  const end = new Date(Date.now() + timer.remaining);
  const ends = end.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
  const progress = live ? 1 - timer.remaining / timer.total : 0;
  return (
    <div className="lock">
      <div className="lock-date">Wednesday 4 November</div>
      <div className="lock-time">9:41</div>
      <div className="live-activity">
        <div className="la-head">
          <div>
            <div className="la-title">
              <I.CircleDashed size={16} /> Focus
            </div>
            <div className="la-sub">{paused ? 'Paused' : live ? `Ends ${ends}` : 'Ready'}</div>
          </div>
          <div className="la-time tabular">{formatTime(timer.remaining)}</div>
        </div>
        <div className="la-bar">
          <i style={{ width: `${progress * 100}%` }} />
        </div>
        <div className="la-controls">
          <button onClick={timer.toggle} tabIndex={-1}>
            {timer.status === 'running' ? <I.Pause size={14} /> : <I.Play size={14} />}
            {timer.status === 'running' ? 'Pause' : paused ? 'Resume' : 'Start'}
          </button>
          <button onClick={timer.reset} tabIndex={-1}>
            <I.Reset size={14} /> Reset
          </button>
        </div>
      </div>
      <div className="lock-corners">
        <span>
          <I.Torch size={20} />
        </span>
        <span>
          <I.Camera size={20} />
        </span>
      </div>
    </div>
  );
}

// ---- Analytics cards (as on the Analytics tab) ------------------------------------------
const WEEK = [
  ['Mon', 2.6],
  ['Tue', 1.4],
  ['Wed', 3.1],
  ['Thu', 2.2],
  ['Fri', 2.8],
  ['Sat', 0.6],
  ['Sun', 0],
];

export function FocusTimeCard() {
  return (
    <div className="ios-card">
      <div className="card-label">Focus time</div>
      <div className="card-big">12h 40m</div>
      <span className="card-chip">+18% vs last week</span>
      <div className="card-stats">
        <div>
          <b>26</b>
          <span>Sessions</span>
        </div>
        <div>
          <b>29m</b>
          <span>Average</span>
        </div>
        <div>
          <b>6/7</b>
          <span>Active days</span>
        </div>
      </div>
      <div className="bars">
        {WEEK.map(([d, h]) => (
          <div key={d} className="bar-col">
            <i style={{ height: `${(h / 3.5) * 100}%` }} />
            <span>{d}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

function heat(i) {
  const week = Math.floor(i / 7);
  const day = i % 7;
  const noise = Math.abs(Math.sin(i * 12.9898) * 43758.5453) % 1;
  const season = 0.55 + 0.35 * Math.sin((week / 26) * Math.PI * 2 + 2.2);
  const v = noise * season * (day >= 5 ? 0.35 : 1);
  return v < 0.12 ? 0 : Math.min(4, Math.ceil(v * 5));
}

export function CalendarCard() {
  return (
    <div className="ios-card">
      <div className="card-row">
        <div>
          <div className="card-title">Focus calendar</div>
          <div className="card-sub">207h focused · 111 active days · best streak 28</div>
        </div>
        <span className="card-year">2026</span>
      </div>
      <div className="heatmap">
        {Array.from({ length: 26 * 7 }, (_, i) => (
          <i key={i} data-l={heat(i)} />
        ))}
      </div>
      <div className="heatmap-legend">
        <span>Less</span>
        {[0, 1, 2, 3, 4].map((l) => (
          <i key={l} data-l={l} />
        ))}
        <span>More</span>
      </div>
    </div>
  );
}
