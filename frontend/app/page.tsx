import type { CSSProperties } from "react";
import Image from "next/image";
import { AppDemo } from "@/components/AppDemo";
import { Details } from "@/components/Details";
import { Downloads } from "@/components/Downloads";
import { RuleViewer } from "@/components/RuleViewer";
import { AppleIcon, ArrowUpRightIcon, GitHubIcon } from "@/components/icons";
import { GITHUB_URL, POKE_URL } from "@/lib/links";

const STEPS = [
  {
    title: "Start blocking…",
    body: "Add a domain, choose timed or untimed protection, and pick 0–3 daily bypasses. Add more domains while blocking or bypassing.",
  },
  {
    title: "A service holds the line",
    body: "A launch daemon owns the hosts and packet-filter rules, session state, keys and deadlines. It starts at boot, and quitting the menu-bar app leaves protection running.",
  },
  {
    title: "End it the way you chose",
    body: "Timed sessions end automatically and cannot be ended early. Untimed sessions need the code delivered to Poke through End protection with key…",
  },
];

const FEATURES = [
  {
    title: "Timed or untimed",
    body: "Timed sessions end on their own. Untimed sessions stay on until you redeem the key.",
  },
  {
    title: "Key delivered to Poke",
    body: "The service generates the unlock key and sends it to Poke. It never returns the key to the UI, and incorrect attempts are rate-limited across restarts.",
  },
  {
    title: "Daily bypasses",
    body: "Bypass… consumes an allowance and temporarily removes the rules. The allowance renews every 24 hours; missed days don’t accumulate.",
  },
  {
    title: "Extra bypass, with approval",
    body: "Request extra bypass from Poke… sends a code that works once, expires after 15 minutes and allows five attempts. Allowance is capped at three.",
  },
  {
    title: "Restores on its own",
    body: "The service checks saved deadlines at startup and every second while awake, catches up after sleep, and restores protection even with the UI closed.",
  },
  {
    title: "A locked-down service",
    body: "IPC accepts defined Muzzle actions only. The helper verifies the user ID and a pinned code signature, not just a bundle identifier.",
  },
];

export default function Home() {
  return (
    <>
      <header className="nav">
        <div className="wrap nav-inner">
          <a className="logo" href="#top" aria-label="Muzzle home">
            <Image className="logo-mark" src="/muzzle.svg" alt="" width={30} height={30} priority />
            Muzzle
          </a>
          <nav className="nav-links" aria-label="Primary">
            <a className="gh-icon" href={GITHUB_URL} target="_blank" rel="noreferrer" aria-label="Muzzle on GitHub">
              <GitHubIcon />
            </a>
            <a className="navlink" href="#download">
              Download
            </a>
          </nav>
        </div>
      </header>

      <main id="top">
        <section className="hero">
          <div className="wrap hero-inner">
            <h1>
              A website blocker that stays{" "}
              <span className="toggle" aria-hidden="true">
                <span className="toggle-knob" />
              </span>
              <span className="sr-only">on</span>.
            </h1>
            <p className="hero-sub">
              Muzzle is a native{" "}
              <span className="brand">
                <AppleIcon className="brand-icon" />
                macOS
              </span>{" "}
              menu-bar app with a privileged background service. Timed sessions end on their own;
              untimed sessions end with a key delivered to{" "}
              <a className="brand" href={POKE_URL} target="_blank" rel="noreferrer">
                <span className="brand-icon brand-mask" style={{ "--icon": "url(/poke.png)" } as CSSProperties} />
                Poke
              </a>
              .
            </p>
            <div className="cta-row">
              <a className="btn" href="#download">
                <AppleIcon className="btn-icon" />
                Download for macOS
              </a>
              <a className="text-link" href={GITHUB_URL} target="_blank" rel="noreferrer">
                View on GitHub <ArrowUpRightIcon className="inline-arrow" />
              </a>
            </div>
            <p className="hero-meta">Requires macOS 13 or later · Apple silicon and Intel</p>
          </div>
          <div className="wrap demo">
            <AppDemo />
          </div>
        </section>

        <section className="sect" id="how" aria-labelledby="how-title">
          <div className="wrap">
            <div className="panel">
              <h2 className="sr-only" id="how-title">
                How a session works
              </h2>
              <ol className="steps">
                {STEPS.map((step, index) => (
                  <li key={step.title} className="cell">
                    <span className="index">{String(index + 1).padStart(2, "0")}</span>
                    <h3>{step.title}</h3>
                    <p>{step.body}</p>
                  </li>
                ))}
              </ol>
            </div>
          </div>
        </section>

        <section className="sect" aria-labelledby="enforce-title">
          <div className="wrap">
            <div className="panel split">
              <div className="p-copy">
                <h2 id="enforce-title">Enforced by a service, not the window.</h2>
                <p>
                  Muzzle inserts localhost IPv4/IPv6 mappings for each domain and its www
                  subdomain inside its marked hosts section, preserving unrelated entries. An
                  isolated <code>com.apple/muzzle</code> PF anchor blocks resolved IPs and clears
                  matching connections.
                </p>
                <p>
                  Root-owned cached DNS results support offline restoration, and Poke
                  notifications never gate enforcement.
                </p>
                <div className="links">
                  <a className="ulink" href={`${GITHUB_URL}#service-security`} target="_blank" rel="noreferrer">
                    Read the security model <ArrowUpRightIcon className="inline-arrow" />
                  </a>
                </div>
              </div>
              <RuleViewer />
            </div>
          </div>
        </section>

        <section className="sect" aria-labelledby="details-title">
          <div className="wrap">
            <h2 className="sect-title" id="details-title">
              Small details, built in
            </h2>
            <div className="panel">
              <Details />
            </div>
          </div>
        </section>

        <section className="sect" aria-labelledby="features-title">
          <div className="wrap">
            <h2 className="sect-title" id="features-title">
              Built to be hard to talk yourself out of
            </h2>
            <div className="panel">
              <ul className="features">
                {FEATURES.map((feature) => (
                  <li key={feature.title} className="cell">
                    <h3>{feature.title}</h3>
                    <p>{feature.body}</p>
                  </li>
                ))}
              </ul>
            </div>
          </div>
        </section>

        <section className="sect" aria-labelledby="limits-title">
          <div className="wrap">
            <div className="panel limits">
              <h2 id="limits-title">Best-effort, by design</h2>
              <div className="limits-copy">
                <p>
                  Rotating IPs, browser Secure DNS, existing connections to unknown IPs and
                  shared CDNs limit accuracy, and blocking shared IPs can affect unrelated sites.
                  This is not hostname-aware filtering. For X, consider both{" "}
                  <code>x.com</code> and <code>api.x.com</code>.
                </p>
                <p>
                  Muzzle stops ordinary unprivileged clients from controlling the helper. It does
                  not stop an administrator who intentionally removes protection.
                </p>
              </div>
            </div>
          </div>
        </section>

        <section className="sect" id="download" aria-labelledby="download-title">
          <div className="wrap">
            <h2 className="sect-title" id="download-title">
              Download Muzzle.
            </h2>
            <p className="sect-lede">Available for macOS 13 or later, on Apple silicon and Intel.</p>
            <div className="panel">
              <Downloads />
            </div>
          </div>
        </section>

        <section className="closing" aria-labelledby="closing-title">
          <div className="wrap">
            <h2 id="closing-title">Stay on task.</h2>
            <p>Muzzle is open source and licensed under AGPL-3.0.</p>
            <div className="cta-row">
              <a className="btn" href="#download">
                <AppleIcon className="btn-icon" />
                Download
              </a>
              <a className="text-link" href={GITHUB_URL} target="_blank" rel="noreferrer">
                Star on GitHub <ArrowUpRightIcon className="inline-arrow" />
              </a>
            </div>
          </div>
        </section>
      </main>

      <footer className="footer">
        <div className="wrap footer-inner">
          <a className="gh-icon" href={GITHUB_URL} target="_blank" rel="noreferrer" aria-label="Muzzle on GitHub">
            <GitHubIcon />
          </a>
          <span>AGPL-3.0 © 2026</span>
        </div>
      </footer>
    </>
  );
}
