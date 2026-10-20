import { ImageResponse } from "next/og";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

export const socialImageSize = { width: 1200, height: 630 };
export const socialImageAlt =
  "Muzzle's menu-bar menu and window blocking websites during a timed session.";

// Read once at module load so the image is generated at build time rather than per request.
const regularFont = await readFile(
  join(process.cwd(), "node_modules/@fontsource/geist/files/geist-latin-400-normal.woff"),
);
const semiboldFont = await readFile(
  join(process.cwd(), "node_modules/@fontsource/geist/files/geist-latin-600-normal.woff"),
);

// Palette matches the dark macOS recreation on the landing page.
const C = {
  window: "#1f1f1f",
  title: "#292929",
  panel: "#2b2b2b",
  line: "rgba(255,255,255,0.09)",
  t1: "#f4f4f4",
  t2: "rgba(255,255,255,0.56)",
  t3: "rgba(255,255,255,0.32)",
  field: "#181818",
  accent: "#85858a",
  light: "#4a4a4d",
  menu: "#262626",
  menuDim: "rgba(255,255,255,0.4)",
  menuSep: "rgba(255,255,255,0.12)",
};

const flex = { display: "flex" } as const;

/** Grayscale impasto: lit fractal noise, darkened so the windows stay the focus. */
function PaintBackground() {
  const { width, height } = socialImageSize;
  return (
    <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`} style={{ position: "absolute", left: 0, top: 0 }}>
      <defs>
        <filter id="paint" x="0" y="0" width="100%" height="100%">
          <feTurbulence type="fractalNoise" baseFrequency="0.011" numOctaves="3" seed="4" result="noise" />
          <feDiffuseLighting in="noise" surfaceScale="16" diffuseConstant="1.3" lightingColor="#ffffff" result="lit">
            <feDistantLight azimuth="225" elevation="52" />
          </feDiffuseLighting>
          <feComponentTransfer in="lit" result="contrast">
            <feFuncR type="gamma" amplitude="0.62" exponent="1.7" offset="0" />
            <feFuncG type="gamma" amplitude="0.62" exponent="1.7" offset="0" />
            <feFuncB type="gamma" amplitude="0.62" exponent="1.7" offset="0" />
          </feComponentTransfer>
        </filter>
      </defs>
      <rect width={width} height={height} filter="url(#paint)" />
    </svg>
  );
}

function Logo({ size, radius }: { size: number; radius: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 18 18" style={{ borderRadius: radius }}>
      <rect width="18" height="18" fill="#000" />
      <g transform="translate(0 18) scale(1 -1)">
        <path d="M4.1 15.2H13.9L16.4 11.3 14.5 2.5H3.5L1.6 11.3Z" fill="#fff" />
        <path d="M5.1 6H12.9M5.1 9H12.9M5.1 12H12.9" fill="none" stroke="#000" strokeWidth="1.2" />
      </g>
    </svg>
  );
}

function Panel({ title, status }: { title: string; status?: string }) {
  return (
    <div
      style={{
        ...flex,
        alignItems: "center",
        height: 68,
        padding: "0 18px",
        background: C.panel,
        borderRadius: 14,
        border: `1px solid ${C.line}`,
      }}
    >
      <svg width="13" height="13" viewBox="0 0 12 12" style={{ marginRight: 10 }}>
        <path d="M4.2 2.2 8 6l-3.8 3.8" fill="none" stroke={C.t1} strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
      <div style={{ ...flex, fontSize: 17, fontWeight: 600 }}>{title}</div>
      <div style={{ ...flex, marginLeft: "auto", fontSize: 13, color: C.t2 }}>{status}</div>
    </div>
  );
}

function AppWindow() {
  return (
    <div
      style={{
        ...flex,
        flexDirection: "column",
        position: "absolute",
        left: 72,
        top: 54,
        width: 628,
        height: 700,
        background: C.window,
        borderRadius: 16,
        border: "1px solid rgba(255,255,255,0.12)",
        boxShadow: "0 30px 80px rgba(0,0,0,0.65)",
        overflow: "hidden",
        color: C.t1,
      }}
    >
      {/* title bar */}
      <div style={{ ...flex, alignItems: "center", justifyContent: "center", position: "relative", height: 32, background: C.title, borderBottom: `1px solid ${C.line}` }}>
        <div style={{ ...flex, position: "absolute", left: 14, gap: 9 }}>
          {[0, 1, 2].map((i) => (
            <div key={i} style={{ width: 13, height: 13, borderRadius: 7, background: C.light }} />
          ))}
        </div>
        <div style={{ ...flex, fontSize: 14, fontWeight: 600, color: C.t2 }}>Muzzle</div>
      </div>

      <div style={{ ...flex, flexDirection: "column", padding: "26px 26px 0", gap: 16 }}>
        <div style={{ ...flex, alignItems: "center", gap: 14 }}>
          <Logo size={44} radius={10} />
          <div style={{ ...flex, fontSize: 31, fontWeight: 600 }}>Muzzle</div>
        </div>
        <div style={{ ...flex, marginTop: -6, fontSize: 16, color: C.t2 }}>
          Blocking 3 websites until 10:11 AM. 1 bypass left.
        </div>

        <Panel title="Poke API key" status="Saved in Keychain" />
        <Panel title="Shortcuts" />
        <Panel title="Saved websites" status="2 saved" />

        <div style={{ ...flex, flexDirection: "column", gap: 18, padding: 18, background: C.panel, borderRadius: 14, border: `1px solid ${C.line}` }}>
          <div style={{ ...flex, fontSize: 17, fontWeight: 600 }}>Add a protected website</div>
          <div style={{ ...flex, alignItems: "center", gap: 14 }}>
            <div style={{ ...flex, width: 78, fontSize: 13, fontWeight: 600, color: C.t2 }}>Website</div>
            <div style={{ ...flex, flex: 1, alignItems: "center", height: 28, padding: "0 9px", background: C.field, borderRadius: 6, border: "1px solid rgba(255,255,255,0.15)", fontSize: 15 }}>
              reddit.com
            </div>
            <div style={{ ...flex, alignItems: "center", justifyContent: "center", height: 28, padding: "0 17px", background: C.accent, borderRadius: 6, fontSize: 15, fontWeight: 600, color: "#fff" }}>
              Block
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

const MENU: { text: string; dim?: boolean; sep?: boolean }[] = [
  { text: "Muzzle", dim: true },
  { text: "Blocking 3 websites until 10:11 AM. 1 bypass left.", dim: true },
  { text: "Bypasses renew Oct 21, 2026 at 9:41 AM", dim: true },
  { text: "", sep: true },
  { text: "Manage protected websites…" },
  { text: "", sep: true },
  { text: "Request extra bypass from Poke…" },
  { text: "Enter bypass approval code…" },
  { text: "", sep: true },
  { text: "Bypass… (1 left)" },
  { text: "", sep: true },
  { text: "Blocking service: running", dim: true },
  { text: "Check for Updates…" },
];

/** BypassWarningController's floating panel, shown two minutes before a bypass ends. */
function Reminder() {
  return (
    <div
      style={{
        ...flex,
        alignItems: "flex-start",
        position: "absolute",
        left: 746,
        top: 410,
        width: 372,
        padding: 18,
        gap: 14,
        background: C.menu,
        borderRadius: 14,
        border: "1px solid rgba(255,255,255,0.14)",
        boxShadow: "0 24px 60px rgba(0,0,0,0.6)",
        color: C.t1,
      }}
    >
      <svg width="26" height="26" viewBox="0 0 24 24">
        <circle cx="12" cy="12" r="9.5" fill="none" stroke={C.t1} strokeWidth="1.6" />
        <path d="M12 6.8V12l3.4 2.1" fill="none" stroke={C.t1} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
      <div style={{ ...flex, flexDirection: "column", gap: 6 }}>
        <div style={{ ...flex, fontSize: 12, color: C.t2 }}>Muzzle</div>
        <div style={{ ...flex, fontSize: 15, fontWeight: 600 }}>2 minutes left in your bypass</div>
        <div style={{ ...flex, fontSize: 13.5, color: C.t2 }}>Protected websites will block again.</div>
      </div>
    </div>
  );
}

function StatusMenu() {
  return (
    <div
      style={{
        ...flex,
        flexDirection: "column",
        position: "absolute",
        left: 746,
        top: 54,
        width: 372,
        padding: 6,
        background: C.menu,
        borderRadius: 12,
        border: "1px solid rgba(255,255,255,0.14)",
        boxShadow: "0 24px 60px rgba(0,0,0,0.6)",
        color: C.t1,
      }}
    >
      {MENU.map((item, index) =>
        item.sep ? (
          <div key={index} style={{ ...flex, height: 1, margin: "6px 0", background: C.menuSep }} />
        ) : (
          <div key={index} style={{ ...flex, padding: "4px 14px", fontSize: 14.5, color: item.dim ? C.menuDim : C.t1 }}>
            {item.text}
          </div>
        ),
      )}
    </div>
  );
}

export function renderSocialImage() {
  return new ImageResponse(
    (
      <div style={{ ...flex, position: "relative", width: "100%", height: "100%", background: "#161616", fontFamily: "Geist", overflow: "hidden" }}>
        <PaintBackground />
        {/* vignette keeps the edges dark so the windows stand out */}
        <div
          style={{
            ...flex,
            position: "absolute",
            left: 0,
            top: 0,
            width: "100%",
            height: "100%",
            backgroundImage: "radial-gradient(ellipse at 50% 45%, rgba(0,0,0,0) 35%, rgba(0,0,0,0.55) 100%)",
          }}
        />
        <AppWindow />
        <StatusMenu />
        <Reminder />
      </div>
    ),
    {
      ...socialImageSize,
      fonts: [
        { name: "Geist", data: regularFont, weight: 400, style: "normal" },
        { name: "Geist", data: semiboldFont, weight: 600, style: "normal" },
      ],
    },
  );
}
