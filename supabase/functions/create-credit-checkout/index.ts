import Stripe from "https://esm.sh/stripe@17.7.0?target=deno";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://enclosurelab.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const PACKAGES = {
  starter: { credits: 500, amount: 499, name: "Starter pack — 500 credits" },
  trader: { credits: 1200, amount: 999, name: "Trader pack — 1,200 credits" },
  pro: { credits: 2600, amount: 1999, name: "Pro pack — 2,600 credits" },
} as const;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
    status, headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
  if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);

  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!stripeKey || !supabaseUrl || !anonKey) {
    return json({ error: "Secure checkout is not configured yet. An administrator must configure payment secrets." }, 503);
  }

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return json({ error: "Please sign in before purchasing credits." }, 401);
  const supabase = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: userError } = await supabase.auth.getUser();
  if (userError || !user) return json({ error: "Your sign-in session is invalid. Please sign in again." }, 401);

  let packageCode: string;
  try { packageCode = (await req.json()).packageCode; }
  catch { return json({ error: "Invalid checkout request." }, 400); }
  if (!Object.hasOwn(PACKAGES, packageCode)) return json({ error: "Unknown credit package." }, 400);
  const pack = PACKAGES[packageCode as keyof typeof PACKAGES];
  try {
    const stripe = new Stripe(stripeKey, { apiVersion: "2024-12-18.acacia" });
    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      payment_method_types: ["card"],
      line_items: [{ price_data: {
        currency: "usd", unit_amount: pack.amount,
        product_data: { name: pack.name, description: "Credits for simulated trading on Lawsons Company Holdings." },
      }, quantity: 1 }],
      client_reference_id: user.id,
      metadata: { user_id: user.id, package_code: packageCode, credits: String(pack.credits) },
      success_url: "https://enclosurelab.github.io/Lawson-s-Company-Holdings-/investments.html?credit_purchase=success",
      cancel_url: "https://enclosurelab.github.io/Lawson-s-Company-Holdings-/investments.html?credit_purchase=cancelled",
    });
    if (!session.url) return json({ error: "The payment provider did not return a checkout URL." }, 502);
    return json({ url: session.url });
  } catch (error) {
    console.error("Stripe checkout creation failed:", error);
    return json({ error: "Could not create checkout. Please try again later." }, 502);
  }
});
