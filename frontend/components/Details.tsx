"use client";

import Image from "next/image";
import { useEffect, useState, type ReactNode } from "react";
import { useReducedMotion } from "@/lib/useReducedMotion";
import styles from "./Details.module.css";

/** Types `text` into a field on a loop; reduced motion shows it already filled in. */
function useTyping(text: string) {
  const reducedMotion = useReducedMotion();
  const [count, setCount] = useState(0);

  useEffect(() => {
    if (reducedMotion) return;
    let cancelled = false;
    const timers: number[] = [];
    const wait = (ms: number) =>
      new Promise<void>((resolve) => timers.push(window.setTimeout(resolve, ms)));

    (async () => {
      while (!cancelled) {
        setCount(0);
        await wait(1500);
        for (let i = 1; i <= text.length; i++) {
          setCount(i);
          await wait(95);
        }
        await wait(3400);
      }
    })();

    return () => {
      cancelled = true;
      timers.forEach((timer) => window.clearTimeout(timer));
    };
  }, [text, reducedMotion]);

  return reducedMotion ? text.length : count;
}

function Field({ children, placeholder, center }: { children: string; placeholder: string; center?: boolean }) {
  return (
    <div className={center ? `${styles.field} ${styles.fieldCenter}` : styles.field}>
      {children ? <span>{children}</span> : <span className={styles.placeholder}>{placeholder}</span>}
      <span className={styles.caret} />
    </div>
  );
}

function Clock() {
  return (
    <svg className={styles.reminderIcon} viewBox="0 0 24 24" aria-hidden="true">
      <circle cx="12" cy="12" r="9.5" fill="none" stroke="currentColor" strokeWidth="1.6" />
      <path d="M12 6.8V12l3.4 2.1" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

/** BypassWarningController: the floating panel shown two minutes before a bypass ends. */
function BypassReminder() {
  return (
    <div className={styles.reminder}>
      <Clock />
      <div className={styles.reminderText}>
        <span className={styles.caption}>Muzzle</span>
        <strong>2 minutes left in your bypass</strong>
        <span className={styles.secondary}>Protected websites will block again.</span>
      </div>
      <svg className={styles.close} viewBox="0 0 12 12" aria-hidden="true">
        <path d="m2.5 2.5 7 7m0-7-7 7" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
      </svg>
    </div>
  );
}

function Alert({ title, body, children, buttons }: { title: string; body: string; children: ReactNode; buttons: ReactNode }) {
  return (
    <div className={styles.alert}>
      <Image src="/muzzle.svg" alt="" width={64} height={64} className={styles.alertIcon} />
      <div>
        <strong className={styles.alertTitle}>{title}</strong>
        <p className={styles.alertBody}>{body}</p>
        <div className={styles.alertField}>{children}</div>
      </div>
      <div className={styles.alertButtons}>{buttons}</div>
    </div>
  );
}

/** AppDelegate.requestWorkContextForPokeDelivery */
function PokeNote() {
  const typed = useTyping("Writing the quarterly report");
  const text = "Writing the quarterly report".slice(0, typed);
  return (
    <Alert
      title="What are you working on?"
      body="Optional — Muzzle will include this with the session key sent to Poke."
      buttons={<span className={`${styles.button} ${styles.primary}`}>Continue</span>}
    >
      <Field placeholder="Optional">{text}</Field>
    </Alert>
  );
}

/** AppDelegate.redeemExtraBypass */
function ApprovalCode() {
  const typed = useTyping("428019");
  return (
    <Alert
      title="Enter bypass approval code"
      body="This adds one bypass without ending protection."
      buttons={
        <>
          <span className={styles.button}>Cancel</span>
          <span className={`${styles.button} ${styles.primary}`}>Add bypass</span>
        </>
      }
    >
      <Field placeholder="Six-digit code from Poke">{"•".repeat(typed)}</Field>
    </Alert>
  );
}

const APPS = ["Finder", "Notes", "Safari", "Terminal"];

/** The Force Quit Applications window (⌘⌥⎋). Muzzle is a menu-bar-only app, so it is not listed. */
function ForceQuit() {
  return (
    <div className={styles.forceQuit}>
      <div className={styles.keys} aria-hidden="true">
        <kbd>⌘</kbd>
        <kbd>⌥</kbd>
        <kbd>esc</kbd>
      </div>
      <div className={styles.fqWindow}>
        <div className={styles.fqTitlebar}>
          <span className={styles.lights}>
            <i />
            <i />
            <i />
          </span>
          <span>Force Quit Applications</span>
        </div>
        <div className={styles.fqBody}>
          <p>If an app doesn’t respond for a while, select its name and click Force Quit.</p>
          <ul className={styles.fqList}>
            {APPS.map((app) => (
              <li key={app}>
                <i className={styles.appGlyph} />
                {app}
              </li>
            ))}
          </ul>
          <div className={styles.fqFooter}>
            <span className={`${styles.button} ${styles.disabled}`}>Force Quit</span>
          </div>
        </div>
      </div>
    </div>
  );
}

// MuzzleIcon.statusImage during a bypass: an outline that fills from the bottom up.
const MASK = "M4.1 15.2H13.9L16.4 11.3 14.5 2.5H3.5L1.6 11.3Z";
const MASK_TOP = 15.2;
const MASK_BOTTOM = 2.5;

function BypassGlyph({ fraction }: { fraction: number }) {
  const fill = (MASK_TOP - MASK_BOTTOM) * fraction;
  return (
    <svg className={styles.bigGlyph} viewBox="0 0 18 18" aria-hidden="true">
      <defs>
        <clipPath id="bypass-clip">
          <path d={MASK} />
        </clipPath>
        <mask id="bypass-grille">
          <rect width="18" height="18" fill="#fff" />
          <g transform="translate(0 18) scale(1 -1)" stroke="#000" strokeWidth="1.2">
            <path d="M5.1 6H12.9M5.1 9H12.9M5.1 12H12.9" />
          </g>
        </mask>
      </defs>
      <g transform="translate(0 18) scale(1 -1)">
        <path d={MASK} fill="none" stroke="currentColor" strokeWidth="1.65" strokeLinejoin="round" />
        <g clipPath="url(#bypass-clip)" mask="url(#bypass-grille)">
          <rect x="1.6" y={MASK_BOTTOM} width="14.8" height={fill} fill="currentColor" />
        </g>
      </g>
    </svg>
  );
}

const BYPASS_MINUTES = 5;

/** While a bypass runs, the menu-bar icon fills one minute at a time until protection returns. */
function BypassCountdown() {
  const reducedMotion = useReducedMotion();
  const [minute, setMinute] = useState(0);

  useEffect(() => {
    if (reducedMotion) return;
    let cancelled = false;
    const timers: number[] = [];
    const wait = (ms: number) =>
      new Promise<void>((resolve) => timers.push(window.setTimeout(resolve, ms)));

    (async () => {
      while (!cancelled) {
        setMinute(0);
        await wait(1600);
        for (let m = 1; m <= BYPASS_MINUTES; m++) {
          setMinute(m);
          await wait(m === BYPASS_MINUTES ? 3200 : 1100);
        }
      }
    })();

    return () => {
      cancelled = true;
      timers.forEach((timer) => window.clearTimeout(timer));
    };
  }, [reducedMotion]);

  const shown = reducedMotion ? 3 : minute;
  const over = shown === BYPASS_MINUTES;
  const status = over
    ? "Blocking 3 websites until 10:41 AM. 0 bypasses left."
    : "Bypass active until 10:20 AM. 0 bypasses left.";

  return (
    <div className={styles.bypass}>
      <div className={styles.slot}>
        <BypassGlyph fraction={shown / BYPASS_MINUTES} />
      </div>
      <div className={styles.ticks}>
        {Array.from({ length: BYPASS_MINUTES }, (_, i) => (
          <i key={i} className={i < shown ? styles.tickOn : undefined} />
        ))}
      </div>
      <div className={styles.minutes}>{over ? "Protection restored" : `${shown} of ${BYPASS_MINUTES} min`}</div>
      <div className={styles.statusPill}>{status}</div>
    </div>
  );
}

/** One shortcut starts a session; ending it asks for the key that only Poke has. */
function ShortcutStory() {
  return (
    <div className={styles.shortcut}>
      <div className={styles.startRow}>
        <div className={styles.caps}>
          {["⌃", "⌥", "⌘", "M"].map((cap) => (
            <kbd key={cap}>{cap}</kbd>
          ))}
        </div>
        <span className={styles.arrow}>→</span>
        <div className={styles.started}>
          <svg viewBox="0 0 14 14" aria-hidden="true">
            <path
              fill="currentColor"
              d="M7 1a3 3 0 0 0-3 3v1.6H3.6C3 5.6 2.6 6 2.6 6.6v5.2c0 .6.4 1 1 1h6.8c.6 0 1-.4 1-1V6.6c0-.6-.4-1-1-1H10V4a3 3 0 0 0-3-3Zm0 1.4A1.6 1.6 0 0 1 8.6 4v1.6H5.4V4A1.6 1.6 0 0 1 7 2.4Z"
            />
          </svg>
          Protection started
        </div>
      </div>
      <div className={styles.endDialog}>
        <Alert
          title="End website blocking?"
          body="Enter this session’s unlock key to remove Muzzle’s entries from your hosts file. Muzzle will remain available in the menu bar."
          buttons={
            <>
              <span className={styles.button}>Cancel</span>
              <span className={`${styles.button} ${styles.primary}`}>End protection</span>
            </>
          }
        >
          <Field center placeholder="Six-digit session code">
            {""}
          </Field>
        </Alert>
      </div>
    </div>
  );
}

const ITEMS = [
  {
    title: "A bypass you can watch run out",
    body: "During a bypass the menu-bar icon starts as an outline and fills one minute at a time. When it’s full, protection is back. Each bypass uses one of your daily allowance.",
    art: <BypassCountdown />,
  },
  {
    title: "A reminder before a bypass ends",
    body: "Two minutes before a bypass runs out, a small floating notice appears and dismisses itself after 12 seconds. A sound is optional.",
    art: <BypassReminder />,
  },
  {
    title: "Extra bypasses need Poke’s approval",
    body: "Request one from the menu, then enter the six-digit code Poke sends you. It adds one bypass without ending protection, and the code works once.",
    art: <ApprovalCode />,
  },
  {
    title: "Easy to start, hard to stop",
    body: "A keyboard shortcut you record, or Control-click on the menu-bar icon, starts a session for your saved websites in one move. Ending an untimed session takes a six-digit key that only goes to Poke, and a timed one can’t be ended early.",
    art: <ShortcutStory />,
  },
  {
    title: "An optional note for Poke",
    body: "Starting an untimed session asks what you’re working on. It’s optional, and it travels to Poke with the session key.",
    art: <PokeNote />,
  },
  {
    title: "Not in the Force Quit window",
    body: "Muzzle lives in the menu bar with no Dock icon, so it doesn’t appear when you press ⌘⌥⎋. Quitting the app wouldn’t switch protection off anyway: the background service keeps enforcing it.",
    art: <ForceQuit />,
  },
];

export function Details() {
  return (
    <ul className="details">
      {ITEMS.map((item) => (
        <li key={item.title} className="detail">
          <div className={styles.art} aria-hidden="true">
            {item.art}
          </div>
          <div className="detail-copy">
            <h3>{item.title}</h3>
            <p>{item.body}</p>
          </div>
        </li>
      ))}
    </ul>
  );
}
