# Square POS integration setup — Lawsons Landscaping

## Status
The repository includes a point-of-sale interface at `pos.html`. It is intentionally **not live and cannot charge cards** until a backend is deployed and configured. Do not treat draft amounts as payments or revenue.

## Required architecture
- Use Square Terminal API for a paired Square Terminal (not browser-side card collection).
- Keep the Square access token and webhook signature key only in Supabase Edge Function secrets. Never place them in HTML, GitHub, or public environment variables.
- The browser sends an authenticated request to a server-side Edge Function with the job reference and amount in integer cents.
- The server validates manager/employee authorization, validates amount and currency, creates a unique idempotency key, and creates a Terminal checkout.
- A Square webhook endpoint validates the Square signature using the exact raw request body and configured notification URL. Handle duplicate webhook event IDs idempotently.
- On a verified completed checkout, retrieve the Square Payment on the server and verify its status is COMPLETED, currency is USD, amount matches the server-side checkout, and payment ID has not already been recorded.
- Only then insert a payment record into the database and update the landscaping totals. Failed, canceled, pending, and duplicate events must not count as revenue.
- Keep refund events and reconciliation in the ledger; never delete completed payment records to adjust totals.

## Before implementation can go live
1. The business owner/authorized adult creates and configures the Square account and Square Developer application.
2. Pair a supported Square Terminal with the application and identify the Square location ID and device ID.
3. Configure Supabase Edge Function secrets for Square access token, location ID, device ID, webhook signature key, and the exact public webhook URL. Use sandbox credentials first.
4. Deploy authenticated checkout and webhook Edge Functions; configure the Square webhook subscription for Terminal checkout and payment updates.
5. Add a database migration for a payment ledger with unique constraints on Square payment ID and webhook event ID, strict row-level security, and an aggregate view for landscaping sales.
6. Test successful, declined, canceled, duplicate-webhook, wrong-amount, and refund scenarios in sandbox before switching to production.

## Official Square documentation
- Terminal quickstart: https://developer.squareup.com/docs/terminal-api/quickstart
- Take one-off payments and verify the payment: https://developer.squareup.com/docs/terminal-api/square-terminal-payments
- Webhooks: https://developer.squareup.com/docs/webhooks/overview
- Payment webhooks: https://developer.squareup.com/docs/payments-api/webhooks
