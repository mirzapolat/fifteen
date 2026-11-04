import { useEffect, useRef, useState } from 'react';
import { Glass, Reveal } from './Glass.jsx';
import { Imprint, Privacy } from './Legal.jsx';
import { formatTime, useFocusTimer } from './timer.js';
import {
  AppRing,
  CalendarCard,
  FocusTimeCard,
  IOSTimer,
  LockScreen,
  MacDesktop,
  ScaledPhone,
} from './Mockups.jsx';
import * as I from './Icons.jsx';

const DOWNLOAD = '/download/mac';
const GITHUB = 'https://github.com/mirzapolat/fifteen';
const SUPPORT = 'https://donate.stripe.com/aFa8wO78f6zndFp2xF0kE03';

// ---- Tiny router -----------------------------------------------------------------
function usePath() {
  const clean = () => window.location.pathname.replace(/\/+$/, '') || '/';
  const [path, setPath] = useState(clean);
  useEffect(() => {
    const onPop = () => setPath(clean());
    window.addEventListener('popstate', onPop);
    return () => window.removeEventListener('popstate', onPop);
  }, []);
  const go = (to) => {
    const [p, hash] = to.split('#');
    const target = p || '/';
    if (target !== path) {
      window.history.pushState({}, '', to);
      setPath(target);
    }
    requestAnimationFrame(() => {
      if (hash) document.getElementById(hash)?.scrollIntoView({ behavior: 'smooth' });
      else window.scrollTo({ top: 0 });
    });
  };
  return [path, go];
}

function Link({ to, go, children, ...rest }) {
  return (
    <a
      href={to}
      onClick={(e) => {
        if (e.metaKey || e.ctrlKey || e.shiftKey || e.button !== 0) return;
        e.preventDefault();
        go(to);
      }}
      {...rest}
    >
      {children}
    </a>
  );
}

// ---- Latest release ------------------------------------------------------------------
function useLatest() {
  const [latest, setLatest] = useState(null);
  useEffect(() => {
    fetch('/api/latest')
      .then((r) => (r.ok ? r.json() : null))
      .then(setLatest)
      .catch(() => {});
  }, []);
  return latest;
}

function DownloadButton({ onDownload, from, large }) {
  return (
    <a
      className={`btn btn--prominent ${large ? 'btn--lg' : ''}`}
      href={DOWNLOAD}
      onClick={() => onDownload(from)}
    >
      <I.Download size={18} />
      <span>Download for Mac</span>
    </a>
  );
}

function IOSButton() {
  return (
    <span className="btn btn--glass is-disabled" aria-disabled="true">
      <I.Phone size={18} />
      <span>Download for iOS</span>
      <span className="soon">Soon</span>
    </span>
  );
}

function Meta({ latest }) {
  return (
    <p className="meta">
      Available for macOS 14 or later{latest?.version && <> · <span className="nowrap">Version {latest.version}</span></>}
    </p>
  );
}

// ---- Nav ---------------------------------------------------------------------------
// [desktop label, phone menu label, target, phone menu icon]
const MENU = [
  ['Mac', 'For Mac', '/#mac', I.Laptop],
  ['iPhone', 'For iPhone & iPad', '/#iphone', I.Phone],
  ['Link', 'Link Devices', '/#link', I.People],
  ['Features', 'Explore Features', '/#features', I.Sparkles],
];

// On touch devices, size the hero to the physical screen: iOS Safari's toolbars float over
// the page, so svh/dvh leave the hero shorter than what you actually see.
function useScreenHeight() {
  useEffect(() => {
    const root = document.documentElement;
    if (!window.matchMedia('(pointer: coarse)').matches) return;
    const set = () => {
      const { width: w, height: h } = window.screen;
      const landscape = window.innerWidth > window.innerHeight;
      root.style.setProperty('--screen-h', `${landscape ? Math.min(w, h) : Math.max(w, h)}px`);
    };
    set();
    window.addEventListener('resize', set);
    return () => {
      window.removeEventListener('resize', set);
      root.style.removeProperty('--screen-h');
    };
  }, []);
}

function Nav({ go, onDownload }) {
  const [compact, setCompact] = useState(false);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    const onScroll = () => setCompact(window.scrollY > 40);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  // While the menu is open: no page scroll, Esc closes, and it closes if the window gets wide.
  useEffect(() => {
    if (!open) return;
    const root = document.documentElement;
    root.classList.add('menu-open');
    const onKey = (e) => e.key === 'Escape' && setOpen(false);
    const mq = window.matchMedia('(min-width: 761px)');
    const onWide = () => mq.matches && setOpen(false);
    window.addEventListener('keydown', onKey);
    mq.addEventListener('change', onWide);
    return () => {
      root.classList.remove('menu-open');
      window.removeEventListener('keydown', onKey);
      mq.removeEventListener('change', onWide);
    };
  }, [open]);

  const goTo = (to) => {
    setOpen(false);
    go(to);
  };

  return (
    <>
      <header className={`nav-wrap ${compact ? 'is-compact' : ''} ${open ? 'is-open' : ''}`}>
        <Glass as="nav" className="nav" aria-label="Main">
          <Link to="/" go={goTo} className="nav-brand" aria-label="Fifteen home">
            <img src="/favicon.png" alt="" width="22" height="22" />
            <span>Fifteen</span>
          </Link>
          <div className="nav-links">
            {MENU.map(([label, , to]) => (
              <Link key={to} to={to} go={go}>
                {label}
              </Link>
            ))}
          </div>
          <a className="btn btn--prominent btn--sm" href={DOWNLOAD} onClick={() => onDownload('nav')}>
            <I.Download size={16} />
            <span className="hide-xs">Download</span>
          </a>
          <button
            className={`nav-burger ${open ? 'is-open' : ''}`}
            aria-label={open ? 'Close menu' : 'Open menu'}
            aria-expanded={open}
            aria-controls="mobile-menu"
            onClick={() => setOpen((o) => !o)}
          >
            <span />
            <span />
          </button>
        </Glass>
      </header>

      <div id="mobile-menu" className={`menu ${open ? 'is-open' : ''}`} aria-hidden={!open} inert={!open}>
        <nav className="menu-links" aria-label="Menu">
          {MENU.map(([, label, to, Icon], i) => (
            <Link key={to} to={to} go={goTo} style={{ '--i': i }}>
              <Icon size={24} className="menu-icon" />
              <span className="menu-title">{label}</span>
            </Link>
          ))}
        </nav>
        <div className="menu-foot" style={{ '--i': MENU.length }}>
          <a
            className="btn btn--prominent btn--lg"
            href={DOWNLOAD}
            onClick={() => {
              onDownload('menu');
              setOpen(false);
            }}
          >
            <I.Download size={18} />
            <span>Download for Mac</span>
          </a>
          <div className="menu-legal">
            <Link to="/imprint" go={goTo}>Imprint</Link>
            <Link to="/privacy" go={goTo}>Privacy</Link>
            <a href={GITHUB} rel="noopener">GitHub</a>
          </div>
        </div>
      </div>
    </>
  );
}

// ---- Hero ------------------------------------------------------------------------------
function Hero({ timer, spectrum, setSpectrum, latest, onDownload, next = 'mac' }) {
  const [drag, setDrag] = useState(null); // minutes while dragging the ring
  const last = useRef(timer.minutes);

  const onDial = (f, phase) => {
    if (phase === 'end') {
      if (drag != null) timer.setMinutes(drag);
      setDrag(null);
      return;
    }
    if (phase === 'start') last.current = timer.minutes;
    let m = Math.round(f * 60) || 60;
    // Don't wrap from 60 to 1 (or back) when the finger crosses 12 o'clock.
    if (last.current >= 45 && m <= 15) m = 60;
    else if (last.current <= 15 && m >= 45) m = 1;
    last.current = m;
    setDrag(m);
  };

  const onKey = (e) => {
    if (timer.status !== 'idle') return;
    const step = { ArrowUp: 1, ArrowRight: 1, ArrowDown: -1, ArrowLeft: -1 }[e.key];
    if (step) {
      e.preventDefault();
      timer.setMinutes(timer.minutes + step);
    }
  };

  const dragging = drag != null;

  return (
    <section className="hero">
      <div className="hero-copy">
        <h1>
          Pomodoro
          <br />
          <span className="dim">made for you.</span>
        </h1>
        <p className="lede">
          Fifteen is a feature-rich, free and open‑source Pomodoro timer to keep you focused, day
          in, day out. Explore what it has to offer!
        </p>
        <div className="cta-row">
          <DownloadButton onDownload={onDownload} from="hero" />
          <IOSButton />
        </div>
        <Meta latest={latest} />
      </div>

      <a
        className="scroll-hint"
        href={`#${next}`}
        aria-label={`Scroll to ${next}`}
        onClick={(e) => {
          e.preventDefault();
          document.getElementById(next)?.scrollIntoView({ behavior: 'smooth' });
        }}
      >
        <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <path d="M6 9.5l6 6 6-6" />
        </svg>
      </a>

      <div className="hero-dial">
        <div
          className="dial-slider"
          role="slider"
          tabIndex={0}
          aria-label="Focus length in minutes"
          aria-valuemin={1}
          aria-valuemax={60}
          aria-valuenow={timer.minutes}
          onKeyDown={onKey}
        >
          <AppRing
            timer={timer}
            spectrum={spectrum}
            size={420}
            lineWidth={6}
            onTap={timer.toggle}
            onDial={timer.status === 'idle' ? onDial : undefined}
            fraction={dragging ? drag / 60 : undefined}
            time={dragging ? formatTime(drag * 60_000) : undefined}
            subtitle={
              dragging ? 'Release to set' : timer.status === 'running' ? 'Pause' : undefined
            }
            symbol={timer.status === 'running' ? 'pause' : undefined}
            className="ring--hero"
          />
        </div>
        <div className="dial-controls">
          <Glass className="segmented" role="radiogroup" aria-label="Ring style">
            <button
              role="radio"
              aria-checked={!spectrum}
              className={!spectrum ? 'is-on' : ''}
              onClick={() => setSpectrum(false)}
            >
              Black & White
            </button>
            <button
              role="radio"
              aria-checked={spectrum}
              className={spectrum ? 'is-on' : ''}
              onClick={() => setSpectrum(true)}
            >
              Rainbow
            </button>
            <span
              className="segmented-thumb"
              style={{ transform: `translateX(${spectrum ? 100 : 0}%)` }}
            />
          </Glass>
          {timer.status !== 'idle' && (
            <button className="btn btn--glass btn--sm" onClick={timer.reset}>
              <I.Reset size={14} /> Reset
            </button>
          )}
        </div>
      </div>
    </section>
  );
}

// ---- Features -----------------------------------------------------------------------------
const FEATURES = [
  [
    'Pomodoro',
    'Everything you’d expect from a classic Pomodoro timer, and nothing less.',
  ],
  [
    'Flowtime',
    'With Flowtime, your session isn’t limited by a timer. Stop whenever you want, and Fifteen works out the right amount of rest.',
  ],
  ['Flow mode', 'In the zone when the bell rings? Keep going. The extra minutes still count.'],
  [
    'Intentions & projects',
    'Write down the one thing you’re working on and file it under a project.',
  ],
  [
    'Rate your sessions',
    'After each session, rate it with up to five stars and add a short note to look back on later.',
  ],
  [
    'Sounds & haptics',
    'A classic bell, a singing bowl, a wood block, a ticking clock, white noise and rain, plus haptic feedback on iPhone.',
  ],
  ['Notifications', 'Fifteen lets you know when it’s time for a break, so you never miss one.'],
  [
    'Siri & Shortcuts',
    'Start, pause or ask how much time is left. Hook Fifteen into your own automations.',
  ],
  ['Private', 'No account, no tracking, no ads. Your data stays on your device.'],
];

const ANALYTICS = [
  [I.Flame, 'Streaks', 'Daily streaks with rest days, if you want them.'],
  [I.Grid, 'Heatmap', 'Every focused day of the year on one calendar.'],
  [I.Clock, 'Best days & hours', 'See which weekdays and times of day you focus best.'],
  [I.Target, 'Goals', 'Set a daily and weekly focus goal and track it.'],
  [I.List, 'Session log', 'Time, length, project, rating and notes for every session.'],
  [I.Folder, 'Projects', 'Organize sessions by project and see how your time splits.'],
  [
    I.ArrowsUpDown,
    'Import & export',
    'Export to CSV or a full backup and restore it any time. Your data never leaves your hands.',
  ],
];

function Features() {
  return (
    <section className="section" id="features">
      <Reveal className="section-head">
        <h2>Features</h2>
      </Reveal>
      <div className="features-grid">
        {FEATURES.map(([t, b], i) => (
          <Reveal key={t} style={{ '--delay': `${(i % 3) * 70}ms` }}>
            <Glass className="tile">
              <h3>{t}</h3>
              <p>{b}</p>
            </Glass>
          </Reveal>
        ))}
      </div>

      <Reveal className="section-head analytics-head" id="analytics">
        <h2>Your Insights</h2>
      </Reveal>
      <div className="analytics">
        <Reveal className="analytics-copy">
          <ul className="analytics-list ios-card">
            {ANALYTICS.map(([Icon, t, b]) => (
              <li key={t}>
                <span className="analytics-icon">
                  <Icon size={18} />
                </span>
                <span>
                  <b>{t}</b>
                  <span>{b}</span>
                </span>
              </li>
            ))}
          </ul>
        </Reveal>
        <Reveal className="analytics-cards" aria-hidden="true">
          <FocusTimeCard />
          <CalendarCard />
        </Reveal>
      </div>
    </section>
  );
}

// ---- Mac ---------------------------------------------------------------------------------------
function MacSection({ timer, spectrum }) {
  return (
    <section className="section" id="mac">
      <Reveal className="section-head">
        <h2>Mac</h2>
        <p className="lede">
          The Mac app sits quietly in your menu bar and stays out of your way while you work.
          Click it to open the controls.
        </p>
      </Reveal>
      <Reveal className="mock-wide">
        <MacDesktop timer={timer} spectrum={spectrum} />
      </Reveal>
      <Reveal as="ul" className="bullets">
        <li>Shows the time, a small ring, or both in the menu bar</li>
        <li>
          <kbd>⌃⌥P</kbd> starts or pauses from any app, <kbd>⌃⌥O</kbd> opens Fifteen
        </li>
        <li>Hides distracting apps while you focus</li>
        <li>Optional full-screen break with a slow breathing circle</li>
        <li>Turns on Do Not Disturb during focus</li>
        <li>Runs your Shortcuts when focus starts or ends</li>
        <li>Pauses when your Mac locks or sleeps</li>
        <li>Opens at login and keeps itself up to date</li>
      </Reveal>
    </section>
  );
}

// ---- iPhone --------------------------------------------------------------------------------------
function PhoneSection({ timer, spectrum }) {
  return (
    <section className="section" id="iphone">
      <Reveal className="section-head">
        <span className="badge">Coming soon</span>
        <h2>iPhone &amp; iPad</h2>
        <p className="lede">
          Soon you’ll be able to use the companion app on iPhone and iPad to track your time, even
          when you’re away from your Mac.
        </p>
      </Reveal>
      <Reveal className="phones">
        <ScaledPhone>
          <IOSTimer timer={timer} spectrum={spectrum} />
        </ScaledPhone>
        <ScaledPhone light>
          <LockScreen timer={timer} />
        </ScaledPhone>
      </Reveal>
      <Reveal as="ul" className="bullets">
        <li>Countdown on the Lock Screen and in the Dynamic Island, with Pause and Reset</li>
        <li>Link, Timer, Analytics and Settings in four tabs</li>
        <li>Keeps the screen on while the timer runs</li>
        <li>Works on iPad and in landscape</li>
      </Reveal>
    </section>
  );
}

// ---- Link --------------------------------------------------------------------------------------
const EVENTS = ['Mira started', 'Jonas added 5 min', 'Mira paused', 'Lena resumed'];

function LinkSection({ timer, spectrum }) {
  const [i, setI] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setI((n) => (n + 1) % EVENTS.length), 2800);
    return () => clearInterval(id);
  }, []);
  return (
    <section className="section" id="link">
      <Reveal className="section-head">
        <h2>Link</h2>
        <p className="lede">
          Focus with friends or your team. Start a group, share the six-letter code, and everyone
          runs on the same timer, on Mac and iPhone. Only the timer is shared.
        </p>
      </Reveal>
      <Reveal className="link-mocks">
        <div className="link-mac">
          <MacDesktop timer={timer} spectrum={spectrum} mode="link" width={560} height={430} />
        </div>
        <ScaledPhone width={260}>
          <IOSTimer timer={timer} spectrum={spectrum} subtitle={EVENTS[i]} />
        </ScaledPhone>
      </Reveal>
    </section>
  );
}

// ---- Download ------------------------------------------------------------------------------------
function DownloadSection({ latest, onDownload, spectrum }) {
  return (
    <section className="section" id="download">
      <Reveal className="final">
        <Glass className="final-card">
          <img
            src="/icon.png"
            alt="Fifteen app icon"
            width="96"
            height="96"
            className={`app-icon ${spectrum ? 'is-spectrum' : ''}`}
          />
          <h2>Get Fifteen</h2>
          <p>What are you waiting for? Give it a try!</p>
          <div className="cta-row cta-row--center">
            <DownloadButton onDownload={onDownload} from="section" large />
          </div>
          <Meta latest={latest} />
          <p className="final-note">iPhone &amp; iPad are coming soon.</p>
        </Glass>
      </Reveal>
    </section>
  );
}

function Footer({ go }) {
  return (
    <footer className="footer">
      <div className="footer-mobile">
        <a className="footer-support" href={SUPPORT} target="_blank" rel="noopener">
          <I.Heart size={16} />
          Support this app
        </a>
        <p className="footer-made">Made with ♥ by Mirza Polat</p>
      </div>
      <span className="footer-copy">© {new Date().getFullYear()} Mirza Polat</span>
      <a className="footer-support footer-support--desktop" href={SUPPORT} target="_blank" rel="noopener">
        <I.Heart size={16} />
        Support this app
      </a>
      <nav aria-label="Legal">
        <Link to="/imprint" go={go}>
          Imprint
        </Link>
        <Link to="/privacy" go={go}>
          Privacy
        </Link>
        <a href={GITHUB} rel="noopener">
          GitHub
        </a>
      </nav>
    </footer>
  );
}

function Toast({ show }) {
  return (
    <div className="toast-wrap" role="status" aria-live="polite">
      {show && (
        <Glass className="toast">
          <I.Download size={18} />
          <span>Downloading. Open the DMG and drag Fifteen into Applications.</span>
        </Glass>
      )}
    </div>
  );
}

// ---- App ------------------------------------------------------------------------------------------
export default function App() {
  const [path, go] = usePath();
  const timer = useFocusTimer(25);
  const latest = useLatest();
  const [spectrum, setSpectrum] = useState(false);
  const [toast, setToast] = useState(false);
  const toastTimer = useRef(0);
  useScreenHeight();

  // Umami counts the click (not a finished download); `from` says which button.
  const onDownload = (from) => {
    window.umami?.track('download', { from });
    setToast(true);
    clearTimeout(toastTimer.current);
    toastTimer.current = setTimeout(() => setToast(false), 6000);
  };

  useEffect(() => {
    const base =
      path === '/imprint'
        ? 'Imprint · Fifteen'
        : path === '/privacy'
          ? 'Privacy · Fifteen'
          : 'Fifteen · Pomodoro timer for Mac';
    document.title = timer.status === 'running' ? `${formatTime(timer.remaining)} · Fifteen` : base;
  }, [path, timer.status, timer.remaining]);

  useEffect(() => {
    document.documentElement.classList.toggle('spectrum', spectrum);
  }, [spectrum]);

  return (
    <>
      <div className="ambient" aria-hidden="true">
        <span className="blob blob--a" />
        <span className="blob blob--b" />
        <span className="blob blob--c" />
      </div>
      <Nav go={go} onDownload={onDownload} />
      <main>
        {path === '/imprint' ? (
          <Imprint go={go} Link={Link} />
        ) : path === '/privacy' ? (
          <Privacy go={go} Link={Link} />
        ) : (
          <>
            <Hero
              timer={timer}
              spectrum={spectrum}
              setSpectrum={setSpectrum}
              latest={latest}
              onDownload={onDownload}
            />
            <MacSection timer={timer} spectrum={spectrum} />
            <PhoneSection timer={timer} spectrum={spectrum} />
            <LinkSection timer={timer} spectrum={spectrum} />
            <Features />
            <DownloadSection latest={latest} onDownload={onDownload} spectrum={spectrum} />
          </>
        )}
      </main>
      <Footer go={go} />
      <Toast show={toast} />
    </>
  );
}
