import type { Metadata } from 'next';
import './globals.css';
export const metadata: Metadata = { title: 'BikeSpare Pro | Spare Parts Management', description: 'Smart inventory, stock and billing for automobile spare parts shops.' };
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) { return <html lang="en"><body>{children}</body></html>; }
