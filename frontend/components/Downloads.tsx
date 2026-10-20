"use client";

import { useEffect, useState } from "react";
import { FirstLaunch } from "./FirstLaunch";
import { AppleIcon, ArrowUpRightIcon } from "./icons";
import { RELEASE_API_URL, RELEASES_URL } from "@/lib/links";

type ReleaseAsset = { name: string; browser_download_url: string };
type Release = { tag_name: string; html_url: string; assets: ReleaseAsset[] };

type Build = {
  arch: "arm64" | "x86_64";
  label: string;
  detail: string;
};

const BUILDS: Build[] = [
  { arch: "arm64", label: "macOS", detail: "Apple silicon · .dmg" },
  { arch: "x86_64", label: "macOS", detail: "Intel · .dmg" },
];

function findAsset(release: Release | null, arch: Build["arch"]) {
  return release?.assets.find((asset) => asset.name.endsWith(`-${arch}.dmg`));
}

export function Downloads() {
  const [release, setRelease] = useState<Release | null>(null);

  useEffect(() => {
    const controller = new AbortController();
    fetch(RELEASE_API_URL, {
      signal: controller.signal,
      headers: { Accept: "application/vnd.github+json" },
    })
      .then((response) => (response.ok ? (response.json() as Promise<Release>) : null))
      .then((data) => setRelease(data))
      .catch(() => {
        // Offline or rate-limited: the buttons fall back to the releases page.
      });
    return () => controller.abort();
  }, []);

  return (
    <div className="downloads">
      <ul className="dl-list">
        {BUILDS.map((build) => {
          const asset = findAsset(release, build.arch);
          return (
            <li key={build.arch}>
              <a
                className="dl-row"
                href={asset?.browser_download_url ?? RELEASES_URL}
                {...(asset ? { download: "" } : { target: "_blank", rel: "noreferrer" })}
              >
                <AppleIcon className="dl-os" />
                <span className="dl-name">{build.label}</span>
                <span className="dl-detail">{build.detail}</span>
                <span className="dl-file">{asset?.name ?? "latest release"}</span>
              </a>
            </li>
          );
        })}
      </ul>
      <p className="dl-meta">
        <span>{release ? `Version ${release.tag_name}` : "Latest version"}</span>
        <span aria-hidden="true">·</span>
        <span>Requires macOS 13 or later</span>
        <span aria-hidden="true">·</span>
        <a href={release?.html_url ?? RELEASES_URL} target="_blank" rel="noreferrer">
          Release notes <ArrowUpRightIcon className="inline-arrow" />
        </a>
      </p>

      <FirstLaunch />
    </div>
  );
}
