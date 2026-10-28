# BikeSpare Pro — Automobile Spare Parts Inventory & Billing

A responsive Next.js + Supabase web app for bike servicing garages and automobile spare-parts stores. It tracks stock inward, sales, low-stock alerts, and printable receipts. Shop accounts are provisioned by the developer; public registration is intentionally not included.

## Stack
- Next.js 14 / React / TypeScript
- Supabase Auth + PostgreSQL + Row Level Security
- Server-side Supabase service role for developer-only account provisioning
- Responsive CSS UI with charcoal and racing-orange automobile styling
- Deployable to Vercel

## Features in this starter
- Dashboard: parts count, total units, today's sales, low-stock alerts
- Inventory: add/search/delete parts, optional prices, minimum stock levels
- Stock inward: add delivered quantities and log supplier/order references
- Billing: cart, quantity validation, selling prices, discounts, payment method
- Atomic checkout in PostgreSQL: receipt, line items, stock deduction, movement history all succeed or fail together
- Sales history and printable receipt pages
- Developer-only shop owner provisioning API
- Per-shop database isolation with Supabase Row Level Security

## 1. Create Supabase project
1. Create a project at https://supabase.com.
2. Open **SQL Editor**, paste and run `supabase/schema.sql`.
3. In **Authentication → Providers → Email**, keep email/password enabled.
4. In **Authentication → Sign In / Providers / User Signups**, disable public signups if the setting is available. The app itself has no public sign-up page.
5. Create your developer login under **Authentication → Users → Add user**. Use an email you control.
6. In SQL Editor, run the developer profile statement at the bottom of `schema.sql`, replacing `you@example.com` with your exact developer email. This assigns the `developer` role. The API also checks the server-side allowlisted email.

## 2. Configure locally
Install Node.js 20 or later. In this folder:

```bash
npm install
cp .env.example .env.local
npm run dev
```

On Windows PowerShell, copy the env file with:

```powershell
Copy-Item .env.example .env.local
```

Fill `.env.local` using **Supabase → Project Settings → API**:
- `NEXT_PUBLIC_SUPABASE_URL`: Project URL
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`: anon/public key
- `SUPABASE_SERVICE_ROLE_KEY`: service_role key (server-only; never expose it in a `NEXT_PUBLIC_` variable)
- `DEVELOPER_ADMIN_EMAIL`: exact email for your developer account
- `NEXT_PUBLIC_DEVELOPER_ADMIN_EMAIL`: same email, used to show the admin screen in the UI
- `NEXT_PUBLIC_DEVELOPER_NAME=Sumit.K`
- `NEXT_PUBLIC_DEVELOPER_PHONE=83xxxxxxxx` (replace with your business contact number)

Open http://localhost:3000/login.

## 3. Create shop owner accounts
1. Sign in using the developer account.
2. Open **Developer Admin**.
3. Create a shop name, owner name, owner email, mobile and initial password.
4. Share login details privately with the owner.

The server route `/api/admin/create-shop` checks the authenticated user's identity and the server-side `DEVELOPER_ADMIN_EMAIL` before it uses the service role key. Do not expose the service role key to the browser.

## 4. Deploy to Vercel
1. Push this project to a private or public GitHub repository.
2. Import it into Vercel.
3. Add the same environment variables in **Project Settings → Environment Variables**. Add `NEXT_PUBLIC_DEVELOPER_ADMIN_EMAIL` as well as the server-only `DEVELOPER_ADMIN_EMAIL` and `SUPABASE_SERVICE_ROLE_KEY`.
4. Deploy. Every push to the connected branch can trigger a new deployment.
5. In Supabase Auth URL Configuration, set your deployed Vercel URL as the Site URL and add it to Redirect URLs if needed.

## Important production checklist
- Replace `83xxxxxxxx` with the business contact number you want customers to see.
- Add your real shop logo, GSTIN/tax fields and address if you need tax-compliant invoices.
- Configure backups, test role isolation with two separate shop accounts, and review Supabase logs before onboarding paying customers.
- Keep the service role key server-only. Never commit `.env.local` to GitHub.
- Consider adding password reset, owner profile settings, CSV/Excel export, barcode scanning and subscription/payment controls before commercial launch.

## Notes / current scope
- Product unit prices are optional in inventory. A selling price is required on each billed line because sale totals must be accurate even when supplier prices change.
- Taxes/GST are not calculated in this starter. Add the correct rules for your business and jurisdiction before using it as a tax invoice.
- The stock inward and checkout RPCs are transactional, so concurrent sales cannot silently sell more pieces than are in stock.
