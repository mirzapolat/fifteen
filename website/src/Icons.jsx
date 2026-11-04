// Small stand-ins for the SF Symbols the app uses, so the mockups read like the real thing.
const base = { viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 1.8, strokeLinecap: 'round', strokeLinejoin: 'round', 'aria-hidden': true };

const make = (children, extra = {}) =>
  function Icon({ size = 16, style, className }) {
    return (
      <svg width={size} height={size} style={style} className={className} {...base} {...extra}>
        {children}
      </svg>
    );
  };

export const CircleDashed = make(<circle cx="12" cy="12" r="7.5" strokeDasharray="2.6 2.4" />);
export const ChevronUpDown = make(<path d="M8 9.5l4-4 4 4M8 14.5l4 4 4-4" />, { strokeWidth: 2.4 });
export const LaptopPhone = make(
  <>
    <rect x="2.5" y="5" width="13" height="9" rx="1.4" />
    <path d="M1 17.5h15" />
    <rect x="17.5" y="8" width="5" height="10.5" rx="1.2" />
  </>,
);
export const Timer = make(
  <>
    <circle cx="12" cy="13" r="7.5" />
    <path d="M12 13V9.2M10 2.8h4" />
  </>,
);
export const TextBubble = make(
  <>
    <path d="M5 4.5h14a2 2 0 0 1 2 2V15a2 2 0 0 1-2 2h-8l-4.5 3.2V17H5a2 2 0 0 1-2-2V6.5a2 2 0 0 1 2-2z" />
    <path d="M7.5 9h9M7.5 12.2h6" />
  </>,
);
export const ChartBar = make(<path d="M5.5 19.5v-6M12 19.5V5M18.5 19.5V10" />, { strokeWidth: 3 });
export const Ellipsis = make(
  <>
    <circle cx="5.5" cy="12" r="1.6" fill="currentColor" stroke="none" />
    <circle cx="12" cy="12" r="1.6" fill="currentColor" stroke="none" />
    <circle cx="18.5" cy="12" r="1.6" fill="currentColor" stroke="none" />
  </>,
);
export const Play = make(<path d="M7.5 4.8v14.4l11.5-7.2z" fill="currentColor" stroke="none" />);
export const Pause = make(<path d="M7 5h3.4v14H7zM13.6 5H17v14h-3.4z" fill="currentColor" stroke="none" />);
export const Reset = make(<path d="M5 12a7 7 0 1 0 2.05-4.95L5 9M5 4.5V9h4.5" />);
export const Cup = make(
  <>
    <path d="M4.5 10h11.5v3.5a5 5 0 0 1-5 5h-1.5a5 5 0 0 1-5-5z" />
    <path d="M16 11h1.4a2.6 2.6 0 0 1 0 5.2H16M8.5 3.5c-1 1 1 2 0 3.2M12 3.5c-1 1 1 2 0 3.2" />
  </>,
);
export const Plus = make(<path d="M12 5v14M5 12h14" strokeWidth="2.2" />);
export const Copy = make(
  <>
    <rect x="8.5" y="8" width="11" height="12.5" rx="2" />
    <path d="M5 15.5V6a2 2 0 0 1 2-2h8" />
  </>,
);
export const Leave = make(<path d="M12.5 4H6.5a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h6M10 12h10.5M17.5 9l3 3-3 3" />);
export const People = make(
  <>
    <circle cx="9" cy="8" r="3.3" />
    <path d="M2.8 19.5c.6-3.6 3.1-5.3 6.2-5.3s5.6 1.7 6.2 5.3" />
    <circle cx="16.8" cy="8.6" r="2.6" />
    <path d="M16.6 14.2c2.6 0 4.4 1.5 4.9 4.6" />
  </>,
);
export const Gear = make(
  <>
    <circle cx="12" cy="12" r="6.6" />
    <circle cx="12" cy="12" r="2.6" />
    <path d="M12 2.6v2.8M12 18.6v2.8M2.6 12h2.8M18.6 12h2.8M5.35 5.35l2 2M16.65 16.65l2 2M5.35 18.65l2-2M16.65 7.35l2-2" strokeWidth="2.6" />
  </>,
);
export const Wifi = make(<path d="M2.5 9a14 14 0 0 1 19 0M5.8 12.4a9.3 9.3 0 0 1 12.4 0M9.1 15.8a4.6 4.6 0 0 1 5.8 0M12 19.2h.01" strokeWidth="2.2" />);
export const Battery = make(
  <>
    <rect x="2" y="7" width="18" height="10" rx="3" />
    <rect x="4" y="9" width="12" height="6" rx="1.4" fill="currentColor" stroke="none" />
    <path d="M22 10.5v3" />
  </>,
);
export const Signal = make(<path d="M3.5 18v-2.5M8.5 18v-5M13.5 18v-7.5M18.5 18V8" strokeWidth="3" />);
export const Toggles = make(
  <>
    <rect x="3" y="4.5" width="18" height="6.5" rx="3.25" />
    <circle cx="17.5" cy="7.75" r="1.6" fill="currentColor" stroke="none" />
    <rect x="3" y="13" width="18" height="6.5" rx="3.25" />
    <circle cx="6.5" cy="16.25" r="1.6" fill="currentColor" stroke="none" />
  </>,
);
export const Search = make(<path d="M10.5 17a6.5 6.5 0 1 0 0-13 6.5 6.5 0 0 0 0 13zM15.3 15.3 20 20" />);
export const Flame = make(<path d="M12 21c-3.9 0-6.5-2.6-6.5-6.2 0-3.4 2.6-5.3 3.5-8.3.4 2 1.6 3.1 2.6 3.6.3-2.5 1.5-4.6 3.4-6.1-.3 3 3.5 5.5 3.5 10.6 0 3.6-2.6 6.4-6.5 6.4z" />);
export const Grid = make(
  <>
    <rect x="3.5" y="3.5" width="7" height="7" rx="1.6" />
    <rect x="13.5" y="3.5" width="7" height="7" rx="1.6" fill="currentColor" />
    <rect x="3.5" y="13.5" width="7" height="7" rx="1.6" fill="currentColor" />
    <rect x="13.5" y="13.5" width="7" height="7" rx="1.6" />
  </>,
);
export const Clock = make(
  <>
    <circle cx="12" cy="12" r="8.5" />
    <path d="M12 7.5V12l3 2" />
  </>,
);
export const Target = make(
  <>
    <circle cx="12" cy="12" r="8.5" />
    <circle cx="12" cy="12" r="4.8" />
    <circle cx="12" cy="12" r="1.3" fill="currentColor" />
  </>,
);
export const List = make(<path d="M9 6.5h11M9 12h11M9 17.5h11M4.5 6.5h.01M4.5 12h.01M4.5 17.5h.01" strokeWidth="2.2" />);
export const ArrowsUpDown = make(<path d="M8 20V4M4 8l4-4 4 4M16 4v16M12 16l4 4 4-4" />);
export const Folder = make(<path d="M3.5 7a2 2 0 0 1 2-2h4l2 2.2h7a2 2 0 0 1 2 2V17a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z" />);
export const Download = make(<path d="M12 3.5v11m0 0 4.2-4.2M12 14.5 7.8 10.3M4.5 19h15" strokeWidth="2" />);
export const Code = make(<path d="M8.5 7 3.5 12l5 5M15.5 7l5 5-5 5" strokeWidth="2" />);
export const Torch = make(<path d="M9 3h6l-1 5H10zM10 8h4v12a2 2 0 0 1-4 0z" />);
export const Camera = make(
  <>
    <path d="M4 8a2 2 0 0 1 2-2h2l1.5-2h5L16 6h2a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z" />
    <circle cx="12" cy="12.5" r="3.4" />
  </>,
);
export const Phone = make(
  <>
    <rect x="6.5" y="2.5" width="11" height="19" rx="2.8" />
    <path d="M10.5 18.5h3" />
  </>,
);
export const Sparkles = make(
  <path d="M10 3.5l1.6 4.4 4.4 1.6-4.4 1.6L10 15.5l-1.6-4.4L4 9.5l4.4-1.6zM17.5 14l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8z" />,
);
export const Laptop = make(
  <>
    <rect x="4" y="5" width="16" height="11" rx="1.6" />
    <path d="M2 19h20" />
  </>,
);
export const Heart = make(
  <path d="M12 20s-7.5-4.6-7.5-10.2A4.3 4.3 0 0 1 12 7.2a4.3 4.3 0 0 1 7.5 2.6C19.5 15.4 12 20 12 20z" />,
);
