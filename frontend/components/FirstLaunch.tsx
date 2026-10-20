"use client";

import Image from "next/image";
import { useEffect, useState, type ReactNode } from "react";
import { useReducedMotion } from "@/lib/useReducedMotion";
import { OPEN_UNNOTARIZED_URL } from "@/lib/links";
import styles from "./FirstLaunch.module.css";

const STEP_MS = 4500;

const STEPS: { title: ReactNode; detail: string }[] = [
  { title: <>Click <strong>Done</strong></>, detail: "in the warning, not Move to Trash." },
  { title: <>Open <strong>System Settings → Privacy &amp; Security</strong></>, detail: "" },
  { title: <>Click <strong>Open Anyway</strong></>, detail: "in the message about Muzzle." },
  { title: <>Authenticate and <strong>confirm</strong></>, detail: "opening the app when prompted." },
];

function Lights() {
  return (
    <span className={styles.lights}>
      <i />
      <i />
      <i />
    </span>
  );
}

/** Step 1: the Gatekeeper warning. */
function Warning() {
  return (
    <div className={styles.alert}>
      <Image src="/muzzle.svg" alt="" width={64} height={64} className={styles.alertIcon} />
      <div>
        <strong className={styles.alertTitle}>“Muzzle” Not Opened</strong>
        <p className={styles.alertBody}>
          Apple could not verify “Muzzle” is free of malware that may harm your Mac or compromise
          your privacy.
        </p>
      </div>
      <div className={styles.alertButtons}>
        <span className={`${styles.button} ${styles.dim}`}>Move to Trash</span>
        <span className={`${styles.button} ${styles.primary} ${styles.target}`}>Done</span>
      </div>
    </div>
  );
}

const PANES = ["Notifications", "Privacy & Security", "Lock Screen"];

/** Steps 2 and 3: System Settings, first the sidebar, then the Security row. */
function Settings({ scrolled }: { scrolled: boolean }) {
  return (
    <div className={styles.settings}>
      <div className={styles.sidebar}>
        <Lights />
        <ul>
          {PANES.map((pane) => {
            const selected = pane === "Privacy & Security";
            return (
              <li
                key={pane}
                className={`${styles.pane} ${selected ? styles.selected : ""} ${selected && !scrolled ? styles.target : ""}`}
              >
                <i />
                {pane}
              </li>
            );
          })}
        </ul>
      </div>
      <div className={styles.content}>
        <h4>Privacy &amp; Security</h4>
        {scrolled ? (
          <div className={styles.security}>
            <span className={styles.label}>Security</span>
            <div className={styles.securityRow}>
              <span>“Muzzle” was blocked to protect your Mac.</span>
              <span className={`${styles.button} ${styles.primary} ${styles.target}`}>Open Anyway</span>
            </div>
          </div>
        ) : (
          <ul className={styles.skeleton}>
            <li />
            <li />
            <li />
          </ul>
        )}
      </div>
    </div>
  );
}

/** Step 4: authenticate, then confirm. */
function Confirm() {
  return (
    <div className={styles.auth}>
      <div className={styles.lock}>
        <svg viewBox="0 0 24 24" aria-hidden="true">
          <rect x="5" y="10.5" width="14" height="9.5" rx="2.2" fill="currentColor" />
          <path d="M8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
        </svg>
      </div>
      <strong>Authenticate</strong>
      <p>Use Touch ID or enter your password to open “Muzzle”.</p>
      <div className={styles.authField}>
        <span>Password</span>
      </div>
      <div className={styles.alertButtons}>
        <span className={styles.button}>Cancel</span>
        <span className={`${styles.button} ${styles.primary} ${styles.target}`}>Open</span>
      </div>
    </div>
  );
}

const SCENES = [<Warning key="warning" />, <Settings key="pane" scrolled={false} />, <Settings key="security" scrolled />, <Confirm key="confirm" />];

export function FirstLaunch() {
  const reducedMotion = useReducedMotion();
  const [active, setActive] = useState(0);

  // Advance on a timer; picking a step by hand restarts it. Reduced motion stays manual.
  useEffect(() => {
    if (reducedMotion) return;
    const timer = window.setTimeout(() => setActive((i) => (i + 1) % STEPS.length), STEP_MS);
    return () => window.clearTimeout(timer);
  }, [active, reducedMotion]);

  return (
    <div className="note">
      <div className={styles.walkthrough}>
        <div>
          <h3 className={styles.title}>First launch</h3>
          <p className={styles.intro}>
            Releases are ad-hoc signed, not Apple-notarized, so macOS may say “Muzzle” Not Opened.
            If you trust the download, here’s how to open it. Don’t disable Gatekeeper globally.{" "}
            <a href={OPEN_UNNOTARIZED_URL} target="_blank" rel="noreferrer">
              Apple’s instructions
            </a>
            .
          </p>
          <ol className={styles.steps}>
            {STEPS.map((step, index) => (
              <li key={index}>
                <button
                  type="button"
                  className={styles.step}
                  aria-current={index === active ? "step" : undefined}
                  onClick={() => setActive(index)}
                >
                  <span className={styles.num}>{index + 1}</span>
                  <span className={styles.stepText}>
                    {step.title} {step.detail}
                    {index === active && !reducedMotion && (
                      <span className={styles.progress} key={active} aria-hidden="true" />
                    )}
                  </span>
                </button>
              </li>
            ))}
          </ol>
        </div>
        <div className={styles.stage} aria-hidden="true">
          <div key={active} className={styles.scene}>
            {SCENES[active]}
          </div>
        </div>
      </div>
    </div>
  );
}
