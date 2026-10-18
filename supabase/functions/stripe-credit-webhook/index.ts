import Stripe from "https://esm.sh/stripe@17.7.0?target=deno";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
  const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const signature = req.headers.get("stripe-signature");
  if (!stripeKey || !webhookSecret || !supabaseUrl || !serviceRoleKey || !signature) {
    return new Response("Webhook configuration incomplete", { status: 500 });
  }
  const stripe = new Stripe(stripeKey, { apiVersion: "2024-12-18.acacia" });
  let event: Stripe.Event;
  try {
    const rawBody = await req.text();
    event = await stripe.webhooks.constructEventAsync(rawBody, signature, webhookSecret, undefined, Stripe.createSubtleCryptoProvider());
  } catch (error) {
    console.error("Stripe webhook signature verification failed:", error);
    return new Response("Invalid signature", { status: 400 });
  }
  if (event.type !== "checkout.session.completed" && event.type !== "checkout.session.async_payment_succeeded") {
    return new Response(JSON.stringify({ received: true }), { status: 200, headers: { "Content-Type": "application/json" } });
  }
  const session = event.data.object as Stripe.Checkout.Session;
  if (session.payment_status !== "paid") return new Response(JSON.stringify({ received: true, pending: true }), { status: 200 });
  const userId = session.metadata?.user_id;
  const packageCode = session.metadata?.package_code;
  const credits = Number(session.metadata?.credits);
  const expected = { starter: { credits: 500, amount: 499 }, trader: { credits: 1200, amount: 999 }, pro: { credits: 2600, amount: 1999 } } as const;
  if (!userId || !packageCode || !Object.hasOwn(expected, packageCode)) return new Response("Missing or invalid checkout metadata", { status: 400 });
  const pack = expected[packageCode as keyof typeof expected];
  if (credits !== pack.credits || session.amount_total !== pack.amount || session.currency !== "usd" || session.mode !== "payment") {
    return new Response("Payment details did not match the credit package", { status: 400 });
  }
  const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { error } = await admin.rpc("apply_credit_purchase", {
    p_user_id: userId,
    p_session_id: session.id,
    p_package_code: packageCode,
    p_credits: pack.credits,
    p_amount_cents: pack.amount,
  });
  if (error) {
    console.error("Could not apply confirmed credit purchase:", error);
    return new Response("Could not apply credits", { status: 500 });
  }
  return new Response(JSON.stringify({ received: true }), { status: 200, headers: { "Content-Type": "application/json" } });
});
