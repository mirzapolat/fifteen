import { useCallback, useEffect, useRef, useState } from 'react';

const MINUTE = 60_000;
export const DIAL_MINUTES = 60; // the ring is a 60-minute kitchen-timer dial

/** A tiny, date-based focus timer, like the app's TimerEngine. */
export function useFocusTimer(initialMinutes = 15) {
  const [minutes, setMinutesState] = useState(initialMinutes);
  const [status, setStatus] = useState('idle'); // idle | running | paused
  const [remaining, setRemaining] = useState(initialMinutes * MINUTE);
  const endAt = useRef(0);

  useEffect(() => {
    if (status !== 'running') return;
    let raf;
    const tick = () => {
      const left = Math.max(0, endAt.current - Date.now());
      setRemaining(left);
      if (left === 0) {
        bell();
        setStatus('idle');
        setRemaining(minutes * MINUTE);
        return;
      }
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [status, minutes]);

  const start = useCallback(() => {
    unlockAudio();
    endAt.current = Date.now() + remaining;
    setStatus('running');
  }, [remaining]);

  const pause = useCallback(() => {
    setRemaining(Math.max(0, endAt.current - Date.now()));
    setStatus('paused');
  }, []);

  const toggle = useCallback(() => (status === 'running' ? pause() : start()), [status, pause, start]);

  const reset = useCallback(() => {
    setStatus('idle');
    setRemaining(minutes * MINUTE);
  }, [minutes]);

  const setMinutes = useCallback(
    (m) => {
      if (status !== 'idle') return;
      const clamped = Math.min(DIAL_MINUTES, Math.max(1, Math.round(m)));
      setMinutesState(clamped);
      setRemaining(clamped * MINUTE);
    },
    [status],
  );

  return {
    minutes,
    status,
    remaining,
    total: minutes * MINUTE,
    dialFraction: remaining / (DIAL_MINUTES * MINUTE),
    progress: remaining / (minutes * MINUTE),
    start,
    pause,
    toggle,
    reset,
    setMinutes,
  };
}

export function formatTime(ms) {
  const s = Math.ceil(ms / 1000);
  const m = Math.floor(s / 60);
  return `${m}:${String(s % 60).padStart(2, '0')}`;
}

// ---- A bell made from scratch, like the app's sounds ----------------------
let ctx;
function unlockAudio() {
  try {
    ctx ??= new (window.AudioContext || window.webkitAudioContext)();
    if (ctx.state === 'suspended') ctx.resume();
  } catch {
    /* no audio, no problem */
  }
}

function bell() {
  if (!ctx) return;
  const now = ctx.currentTime;
  const master = ctx.createGain();
  master.gain.value = 0.18;
  master.connect(ctx.destination);
  // Inharmonic partials give it the shimmer of a small bowl.
  [
    [1, 1, 3.2],
    [2.76, 0.45, 2.2],
    [5.4, 0.22, 1.4],
    [8.93, 0.1, 0.9],
  ].forEach(([ratio, level, decay]) => {
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.frequency.value = 528 * ratio;
    gain.gain.setValueAtTime(0, now);
    gain.gain.linearRampToValueAtTime(level, now + 0.01);
    gain.gain.exponentialRampToValueAtTime(0.0001, now + decay);
    osc.connect(gain).connect(master);
    osc.start(now);
    osc.stop(now + decay + 0.1);
  });
}
