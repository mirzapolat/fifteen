import { useEffect, useId, useRef, useState } from 'react';

// The app's hand-picked, equally luminous stops: sky → blue → violet → magenta → pink → coral → orange.
const PALETTE = [
  [0.18, 0.76, 1.0],
  [0.3, 0.5, 1.0],
  [0.55, 0.38, 1.0],
  [0.85, 0.32, 0.95],
  [1.0, 0.32, 0.6],
  [1.0, 0.44, 0.36],
  [1.0, 0.6, 0.24],
];

/** Out along the palette over the first half of the ring, back over the second: no seam at the top. */
export function hue(position) {
  let p = position % 1;
  if (p < 0) p += 1;
  const walk = (p < 0.5 ? p * 2 : (1 - p) * 2) * (PALETTE.length - 1);
  const i = Math.min(Math.floor(walk), PALETTE.length - 2);
  const t = walk - i;
  const [a, b] = [PALETTE[i], PALETTE[i + 1]];
  const mix = (k) => Math.round((a[k] + (b[k] - a[k]) * t) * 255);
  return `rgb(${mix(0)} ${mix(1)} ${mix(2)})`;
}

const C = 100; // viewBox center
const point = (r, f) => {
  const a = f * 2 * Math.PI - Math.PI / 2;
  return [C + r * Math.cos(a), C + r * Math.sin(a)];
};

function arcPath(r, from, to) {
  const [x1, y1] = point(r, from);
  const [x2, y2] = point(r, to);
  const large = to - from > 0.5 ? 1 : 0;
  return `M ${x1.toFixed(3)} ${y1.toFixed(3)} A ${r} ${r} 0 ${large} 1 ${x2.toFixed(3)} ${y2.toFixed(3)}`;
}

function Arc({ r, fraction, width, spectrum, drift, segments = 90 }) {
  const f = Math.min(Math.max(fraction, 0), 0.99999);
  if (f <= 0.0005) return null;
  if (!spectrum) {
    return <path d={arcPath(r, 0, f)} stroke="currentColor" strokeWidth={width} strokeLinecap="round" fill="none" />;
  }
  const parts = [];
  const n = Math.max(1, Math.ceil(f * segments));
  for (let i = 0; i < n; i++) {
    const a = (i / n) * f;
    const b = Math.min(f, ((i + 1) / n) * f + 0.002);
    parts.push(
      <path key={i} d={arcPath(r, a, b)} stroke={hue((a + b) / 2 + drift)} strokeWidth={width} fill="none" />,
    );
  }
  return (
    <>
      <circle cx={point(r, 0)[0]} cy={point(r, 0)[1]} r={width / 2} fill={hue(drift)} />
      {parts}
    </>
  );
}

/**
 * The ring. `fraction` is how full it is (0…1). With `onDial`, the outer band can be dragged
 * like a kitchen timer and reports the dial position (0…1). `children` sit in the middle.
 */
export default function Ring({ fraction, spectrum = false, animate = false, width = 6, ticks = false, onDial, label, children, className = '' }) {
  const id = useId().replace(/:/g, '');
  const svg = useRef(null);
  const dragging = useRef(false);
  const [drift, setDrift] = useState(0);
  const r = 100 - width * 2.2;

  useEffect(() => {
    if (!spectrum || !animate) return;
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    let raf;
    const start = performance.now() - drift * 24000;
    const loop = (t) => {
      setDrift(((t - start) / 24000) % 1);
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [spectrum, animate]);

  const dialAt = (e) => {
    const rect = svg.current.getBoundingClientRect();
    const dx = e.clientX - (rect.left + rect.width / 2);
    const dy = e.clientY - (rect.top + rect.height / 2);
    let f = Math.atan2(dx, -dy) / (2 * Math.PI);
    if (f < 0) f += 1;
    return { f, dist: Math.hypot(dx, dy) / (rect.width / 2) };
  };

  const handlers = onDial
    ? {
        onPointerDown: (e) => {
          const { f, dist } = dialAt(e);
          if (dist < 0.6) return;
          dragging.current = true;
          svg.current.setPointerCapture(e.pointerId);
          onDial(f, 'start');
        },
        onPointerMove: (e) => {
          if (dragging.current) onDial(dialAt(e).f, 'move');
        },
        onPointerUp: () => {
          if (dragging.current) onDial(null, 'end');
          dragging.current = false;
        },
        onPointerCancel: () => {
          if (dragging.current) onDial(null, 'end');
          dragging.current = false;
        },
      }
    : {};

  const head = point(r, Math.min(fraction, 0.99999));
  const headColor = spectrum ? hue(fraction + drift) : 'currentColor';

  return (
    <div className={`ring ${onDial ? 'ring--dial' : ''} ${className}`} aria-label={label}>
      <svg ref={svg} viewBox="0 0 200 200" {...handlers} aria-hidden="true">
        <defs>
          <filter id={`glow-${id}`} x="-20%" y="-20%" width="140%" height="140%">
            <feGaussianBlur stdDeviation={width * 1.6} />
          </filter>
        </defs>
        <circle cx={C} cy={C} r={r} className="ring-track" strokeWidth={width} fill="none" />
        {ticks &&
          Array.from({ length: 12 }, (_, i) => {
            const [x1, y1] = point(r - width * 2.4, i / 12);
            const [x2, y2] = point(r - width * 3.4, i / 12);
            return <line key={i} x1={x1} y1={y1} x2={x2} y2={y2} className="ring-tick" />;
          })}
        {spectrum && (
          <g filter={`url(#glow-${id})`} opacity="0.75">
            <Arc r={r} fraction={fraction} width={width * 1.6} spectrum drift={drift} segments={36} />
          </g>
        )}
        <Arc r={r} fraction={fraction} width={width} spectrum={spectrum} drift={drift} />
        {fraction > 0.0005 && (
          <circle
            cx={head[0]}
            cy={head[1]}
            r={width * 1.1}
            fill={headColor}
            style={spectrum ? { filter: `drop-shadow(0 0 ${width * 1.2}px ${headColor})` } : undefined}
          />
        )}
      </svg>
      {children && <div className="ring-center">{children}</div>}
    </div>
  );
}
