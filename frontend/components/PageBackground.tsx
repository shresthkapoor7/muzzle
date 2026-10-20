"use client";

import { useEffect, useRef } from "react";
import { DOG_ASCII } from "@/lib/dog-ascii";

/**
 * Fixed backdrop: a very faint ASCII dog in a muzzle, whose glyphs brighten in a soft
 * circle around the pointer. The look lives in `.page-bg` in globals.css.
 */
export function PageBackground() {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    let frame = 0;
    let x = 0;
    let y = 0;

    const onMove = (event: PointerEvent) => {
      if (event.pointerType === "touch") return;
      x = event.clientX;
      y = event.clientY;
      if (frame) return;
      frame = requestAnimationFrame(() => {
        frame = 0;
        el.style.setProperty("--mx", `${x}px`);
        el.style.setProperty("--my", `${y}px`);
        el.style.setProperty("--glow", "1");
      });
    };
    const onLeave = () => el.style.setProperty("--glow", "0");

    window.addEventListener("pointermove", onMove, { passive: true });
    document.documentElement.addEventListener("pointerleave", onLeave);
    return () => {
      cancelAnimationFrame(frame);
      window.removeEventListener("pointermove", onMove);
      document.documentElement.removeEventListener("pointerleave", onLeave);
    };
  }, []);

  return (
    <div ref={ref} className="page-bg" aria-hidden="true">
      <pre className="ascii">{DOG_ASCII}</pre>
      <div className="ascii-lit">
        <pre className="ascii">{DOG_ASCII}</pre>
      </div>
    </div>
  );
}
