/**
 * The Radian "Sweep": a sector exactly one radian wide (its arc is as long as
 * its radius). Dispatch sweeping a search radius from an origin and landing on
 * a live vehicle, the amber dot.
 */
export function RadianMark({
  size = 32,
  color = "var(--accent-fg)",
  ground = "var(--panel-solid)",
  simplified = size < 40,
  label,
}: {
  size?: number;
  /** The sweep; defaults to Signal on dark, Radian Blue on light. */
  color?: string;
  /** What the mark sits on: the ring that separates the vehicle dot. */
  ground?: string;
  /** Drops the inner arc and pivot; on by default below 40 px. */
  simplified?: boolean;
  /** Accessible name; omit when the mark sits next to the wordmark. */
  label?: string;
}) {
  return (
    <svg width={size} height={size} viewBox="0 0 64 64" role={label ? "img" : undefined} aria-label={label} aria-hidden={label ? undefined : true}>
      <path d="M15 46 L49 46 A34 34 0 0 0 33.37 17.39 Z" fill={color} fillOpacity={simplified ? 0.28 : 0.2} />
      {!simplified && (
        <path d="M35 46 A20 20 0 0 0 25.81 29.17" fill="none" stroke={color} strokeOpacity={0.6} strokeWidth={3} strokeLinecap="round" />
      )}
      <path d="M49 46 A34 34 0 0 0 33.37 17.39" fill="none" stroke={color} strokeWidth={simplified ? 6 : 5} strokeLinecap="round" />
      <line x1="15" y1="46" x2="49" y2="46" stroke={color} strokeWidth={simplified ? 5 : 3} strokeLinecap="round" />
      {!simplified && <circle cx="15" cy="46" r="3.5" fill={color} />}
      <circle cx="33.37" cy="17.39" r={simplified ? 7 : 6} fill="#F59E0B" stroke={ground} strokeWidth="2.5" />
    </svg>
  );
}

/** The lowercase "radian" wordmark. */
export function Wordmark({ className = "" }: { className?: string }) {
  return <span className={`font-semibold tracking-[-0.045em] ${className}`}>radian</span>;
}
