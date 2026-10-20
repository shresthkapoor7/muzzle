"use client";

import { useEffect, useState, type CSSProperties } from "react";

type Tone = "plain" | "dim" | "comment" | "hot";
type Line = { text: string; tone: Tone };

type RuleFile = { path: string; lines: Line[] };

// Mirrors what Muzzle writes (HostsFileController / PacketFilterController).
// The domain and IP addresses are placeholders from reserved documentation ranges.
const FILES: RuleFile[] = [
  {
    path: "/etc/hosts",
    lines: [
      { text: "127.0.0.1       localhost", tone: "dim" },
      { text: "255.255.255.255 broadcasthost", tone: "dim" },
      { text: "::1             localhost", tone: "dim" },
      { text: "", tone: "plain" },
      { text: "# MUZZLE_BEGIN — managed by Muzzle", tone: "comment" },
      { text: "# These entries are intentionally managed by Muzzle.", tone: "comment" },
      { text: "127.0.0.1 example.com", tone: "hot" },
      { text: "127.0.0.1 www.example.com", tone: "hot" },
      { text: "::1 example.com", tone: "hot" },
      { text: "::1 www.example.com", tone: "hot" },
      { text: "", tone: "plain" },
      { text: "# MUZZLE_END", tone: "comment" },
    ],
  },
  {
    path: "/etc/pf.anchors/muzzle",
    lines: [
      {
        text: "# This anchor is managed by Muzzle. Do not edit while protection is active.",
        tone: "comment",
      },
      { text: "table <muzzle_ipv4> persist { 192.0.2.10, 192.0.2.11 }", tone: "hot" },
      { text: "block return out quick inet to <muzzle_ipv4>", tone: "hot" },
      { text: "table <muzzle_ipv6> persist { 2001:db8::10 }", tone: "hot" },
      { text: "block return out quick inet6 to <muzzle_ipv6>", tone: "hot" },
    ],
  },
];

const CYCLE_MS = 8000;

export function RuleViewer() {
  const [active, setActive] = useState(0);

  // Advance on a timer; picking a tab by hand restarts it.
  useEffect(() => {
    const timer = window.setTimeout(() => setActive((i) => (i + 1) % FILES.length), CYCLE_MS);
    return () => window.clearTimeout(timer);
  }, [active]);

  const file = FILES[active];

  return (
    <div className="p-view">
      <div className="stage">
        <div className="rv">
          <div className="rv-tabs" role="tablist" aria-label="Files Muzzle writes">
            {FILES.map((f, index) => (
              <button
                key={f.path}
                type="button"
                role="tab"
                id={`rv-tab-${index}`}
                aria-selected={index === active}
                aria-controls="rv-panel"
                className="rv-tab"
                onClick={() => setActive(index)}
              >
                {f.path}
                {index === active && <span className="rv-progress" key={active} aria-hidden="true" />}
              </button>
            ))}
          </div>
          <div className="rv-body" role="tabpanel" id="rv-panel" aria-labelledby={`rv-tab-${active}`}>
            {/* keyed by tab so every switch replays the line-by-line reveal */}
            <div key={active} className="rv-lines">
              {file.lines.map((line, index) => (
                <div
                  key={index}
                  className={`rv-line ${line.tone}`}
                  style={{ "--i": index } as CSSProperties}
                >
                  {line.text}
                </div>
              ))}
            </div>
          </div>
        </div>
        <p className="rv-caption">Illustrative: example.com and documentation IP addresses.</p>
      </div>
    </div>
  );
}
