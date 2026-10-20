import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import { PageBackground } from "@/components/PageBackground";
import { SITE_URL } from "@/lib/links";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
  display: "swap",
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
  display: "swap",
});

const description =
  "A native macOS menu-bar website blocker with a privileged background service.";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: "Muzzle — a website blocker that stays on",
  description,
  openGraph: {
    url: SITE_URL,
    title: "Muzzle",
    description,
    siteName: "Muzzle",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Muzzle",
    description,
  },
};

export const viewport: Viewport = {
  colorScheme: "dark light",
  themeColor: [
    { media: "(prefers-color-scheme: dark)", color: "#0d0d0d" },
    { media: "(prefers-color-scheme: light)", color: "#fafafa" },
  ],
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${geistSans.variable} ${geistMono.variable}`}>
      <body>
        <PageBackground />
        {children}
      </body>
    </html>
  );
}
