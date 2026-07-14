import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "ChainLedger — Workspace setup",
  description: "Create a ChainLedger workspace and select its EVM network.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
