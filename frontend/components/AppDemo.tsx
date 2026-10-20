"use client";

import Image from "next/image";
import { useEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";
import { useReducedMotion } from "@/lib/useReducedMotion";
import { AppleIcon } from "./icons";
import styles from "./AppDemo.module.css";

// Layout of the recreated macOS desktop, in design pixels. The scene is scaled to fit.
const FULL_WIDTH = 1000;
const COMPACT_WIDTH = 600;
const HEIGHT = 800;
const COMPACT_BREAKPOINT = 720;

const BASE_DOMAINS = ["youtube.com", "x.com"];
const NEW_DOMAIN = "reddit.com";
const SESSION_END = "10:11 AM";

function statusMessage(count: number) {
  return `Blocking ${count} ${count === 1 ? "website" : "websites"} until ${SESSION_END}. 1 bypass left.`;
}

/** Plays the flow from the README: add a website while a timed session is running. */
function useDemoScript() {
  const reducedMotion = useReducedMotion();
  const [domains, setDomains] = useState(BASE_DOMAINS);
  const [typed, setTyped] = useState("");
  const [pressed, setPressed] = useState(false);

  useEffect(() => {
    if (reducedMotion) return;

    let cancelled = false;
    const timers: number[] = [];
    const wait = (ms: number) =>
      new Promise<void>((resolve) => timers.push(window.setTimeout(resolve, ms)));

    (async () => {
      while (!cancelled) {
        setDomains(BASE_DOMAINS);
        setTyped("");
        await wait(2400);
        for (let i = 1; i <= NEW_DOMAIN.length; i++) {
          setTyped(NEW_DOMAIN.slice(0, i));
          await wait(85);
        }
        await wait(650);
        setPressed(true);
        await wait(170);
        setPressed(false);
        setDomains([...BASE_DOMAINS, NEW_DOMAIN]);
        setTyped("");
        await wait(5400);
      }
    })();

    return () => {
      cancelled = true;
      timers.forEach((timer) => window.clearTimeout(timer));
    };
  }, [reducedMotion]);

  // Reduced motion gets the finished frame instead of the loop.
  if (reducedMotion) return { domains: [...BASE_DOMAINS, NEW_DOMAIN], typed: "", pressed: false };
  return { domains, typed, pressed };
}

/** Scale the fixed-size scene to its container; narrow screens crop to just the window. */
function useSceneScale() {
  const ref = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState<{ scale: number; width: number } | null>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const measure = () => {
      const available = el.clientWidth;
      const width = available < COMPACT_BREAKPOINT ? COMPACT_WIDTH : FULL_WIDTH;
      setSize({ scale: Math.min(1, available / width), width });
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  return { ref, size };
}

function Chevron() {
  return (
    <svg className={styles.chevron} viewBox="0 0 12 12" aria-hidden="true">
      <path d="M4.2 2.2 8 6l-3.8 3.8" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function Lock() {
  return (
    <svg className={styles.lock} viewBox="0 0 14 14" aria-hidden="true">
      <path
        fill="currentColor"
        d="M7 1a3 3 0 0 0-3 3v1.6H3.6C3 5.6 2.6 6 2.6 6.6v5.2c0 .6.4 1 1 1h6.8c.6 0 1-.4 1-1V6.6c0-.6-.4-1-1-1H10V4a3 3 0 0 0-3-3Zm0 1.4A1.6 1.6 0 0 1 8.6 4v1.6H5.4V4A1.6 1.6 0 0 1 7 2.4Z"
      />
    </svg>
  );
}

function ClockFill() {
  return (
    <svg className={styles.footIcon} viewBox="0 0 14 14" aria-hidden="true">
      <circle cx="7" cy="7" r="6" fill="currentColor" />
      <path d="M7 3.6V7l2.3 1.5" fill="none" style={{ stroke: "var(--mac-panel)" }} strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function CheckCircle() {
  return (
    <svg className={styles.statusIcon} viewBox="0 0 14 14" aria-hidden="true">
      <circle cx="7" cy="7" r="6" fill="currentColor" />
      <path d="m4.3 7.2 1.9 1.9 3.5-3.9" fill="none" style={{ stroke: "var(--mac-panel)" }} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

/** The active menu-bar glyph (MuzzleIcon.statusImage): outlined mask, filled, grille knocked out. */
function StatusGlyph() {
  return (
    <svg className={styles.glyph} viewBox="0 0 18 18" aria-hidden="true">
      <defs>
        <mask id="muzzle-grille">
          <rect width="18" height="18" fill="#fff" />
          <g transform="translate(0 18) scale(1 -1)" stroke="#000" strokeWidth="1.2">
            <path d="M5.1 6H12.9M5.1 9H12.9M5.1 12H12.9" />
          </g>
        </mask>
      </defs>
      <g transform="translate(0 18) scale(1 -1)" mask="url(#muzzle-grille)">
        <path d="M4.1 15.2H13.9L16.4 11.3 14.5 2.5H3.5L1.6 11.3Z" fill="currentColor" stroke="currentColor" strokeWidth="1.65" strokeLinejoin="round" />
      </g>
    </svg>
  );
}

function Panel({ title, status }: { title: string; status?: ReactNode }) {
  return (
    <div className={styles.panel}>
      <div className={styles.panelHead}>
        <Chevron />
        <span className={styles.panelTitle}>{title}</span>
        <span className={styles.panelStatus}>{status}</span>
      </div>
    </div>
  );
}

function MenuItem({ children, disabled }: { children: ReactNode; disabled?: boolean }) {
  return <div className={disabled ? `${styles.menuItem} ${styles.menuDisabled}` : styles.menuItem}>{children}</div>;
}

export function AppDemo() {
  const { domains, typed, pressed } = useDemoScript();
  const { ref, size } = useSceneScale();
  const status = statusMessage(domains.length);
  const blockDisabled = typed.length === 0;

  const wrapperStyle: CSSProperties = size
    ? { height: HEIGHT * size.scale }
    : { height: HEIGHT * 0.5, visibility: "hidden" };
  const stageStyle: CSSProperties = size
    ? { width: size.width, transform: `scale(${size.scale})` }
    : { width: FULL_WIDTH };

  return (
    <div
      className={styles.frame}
      role="img"
      aria-label="Muzzle's menu-bar menu and window during a timed session, adding a third protected website."
    >
      <div ref={ref} className={styles.fit} style={wrapperStyle}>
        <div className={styles.stage} style={stageStyle} data-compact={size?.width === COMPACT_WIDTH} aria-hidden="true">
          {/* menu bar */}
          <div className={styles.menubar}>
            {/* Muzzle is a menu-bar-only app, so the bar shows the frontmost app instead */}
            <span className={styles.menubarLeft}>
              <AppleIcon className={styles.apple} />
              <span className={styles.appName}>Finder</span>
              <span>File</span>
              <span>Edit</span>
              <span>View</span>
              <span>Go</span>
              <span>Window</span>
              <span>Help</span>
            </span>
            <span className={styles.menubarRight}>
              <span className={`${styles.menubarItem} ${styles.menuOpen}`}>
                <StatusGlyph />
              </span>
              <span className={styles.clock}>Tue 9:52 AM</span>
            </span>
          </div>

          {/* status-item menu (StatusItemController.makeMenu, active timed session) */}
          <div className={styles.menu}>
            <MenuItem disabled>Muzzle</MenuItem>
            <MenuItem disabled>{status}</MenuItem>
            <MenuItem disabled>Bypasses renew Oct 21, 2026 at 9:41 AM</MenuItem>
            <div className={styles.menuSep} />
            <MenuItem>Manage protected websites…</MenuItem>
            <div className={styles.menuSep} />
            <MenuItem>Request extra bypass from Poke…</MenuItem>
            <MenuItem>Enter bypass approval code…</MenuItem>
            <div className={styles.menuSep} />
            <MenuItem>Bypass… (1 left)</MenuItem>
            <div className={styles.menuSep} />
            <MenuItem disabled>Blocking service: running</MenuItem>
            <MenuItem>Check for Updates…</MenuItem>
          </div>

          {/* management window (ManagementWindowController) */}
          <div className={styles.window}>
            <div className={styles.titlebar}>
              <span className={styles.lights}>
                <i />
                <i />
                <i />
              </span>
              <span className={styles.title}>Muzzle</span>
            </div>

            <div className={styles.scroll}>
              <div className={styles.header}>
                <Image src="/muzzle.svg" alt="" width={36} height={36} className={styles.appIcon} />
                <span className={styles.name}>Muzzle</span>
              </div>
              <p className={styles.statusLine}>{status}</p>

              <Panel
                title="Poke API key"
                status={
                  <>
                    <CheckCircle /> Saved in Keychain
                  </>
                }
              />
              <Panel title="Shortcuts" />
              <Panel title="Saved websites" status="2 saved" />

              <div className={styles.panel}>
                <h3 className={styles.panelHeading}>Add a protected website</h3>
                <div className={styles.formRow}>
                  <span className={styles.formLabel}>Website</span>
                  <div className={styles.field}>
                    {typed ? (
                      <span>{typed}</span>
                    ) : (
                      <span className={styles.placeholder}>example.com</span>
                    )}
                    <span className={styles.caret} />
                  </div>
                  <span
                    className={`${styles.button} ${blockDisabled ? styles.buttonDisabled : ""} ${pressed ? styles.buttonPressed : ""}`}
                  >
                    Block
                  </span>
                </div>
                <p className={styles.help}>
                  Use a domain such as youtube.com; its www version is included too.
                </p>
              </div>

              <div className={styles.listBlock}>
                <h3 className={styles.listHeading}>Protected websites</h3>
                <ul className={styles.list}>
                  {domains.map((domain) => (
                    <li key={domain} className={styles.row}>
                      <span>{domain}</span>
                      <Lock />
                    </li>
                  ))}
                </ul>
              </div>
            </div>

            <div className={styles.pinned}>
              <label className={styles.toggle}>
                <span className={styles.checkbox} />
                Play a sound with the 2-minute bypass reminder
              </label>
              <div className={styles.footer}>
                <ClockFill />
                This timed session ends automatically.
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
