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

function Field({ children, placeholder }: { children: string; placeholder: string }) {
  return (
    <div className={styles.field}>
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

const ITEMS = [
  {
    title: "A reminder before a bypass ends",
    body: "Two minutes before a bypass runs out, a small floating notice appears and dismisses itself after 12 seconds. A sound is optional.",
    art: <BypassReminder />,
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
  {
    title: "Extra bypasses need Poke’s approval",
    body: "Request one from the menu, then enter the six-digit code Poke sends you. It adds one bypass without ending protection, and the code works once.",
    art: <ApprovalCode />,
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
