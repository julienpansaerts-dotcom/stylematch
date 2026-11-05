// Reçoit les événements Stripe. Paiement réussi => la commande est créée et
// les pièces disparaissent de tous les paniers. Paiement annulé => les pièces
// sont libérées. Si une pièce a échappé à l'acheteur, elle est remboursée.
import Stripe from "npm:stripe@23.0.0";
import { adminClient, env, json, serve, stripeClient } from "../_shared/clients.ts";

const cryptoProvider = Stripe.createSubtleCryptoProvider();

serve(async (req) => {
  const signature = req.headers.get("Stripe-Signature");
  if (!signature) return json({ error: "Signature manquante." }, 400);

  const stripe = stripeClient();
  const payload = await req.text();
  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      payload,
      signature,
      env("STRIPE_WEBHOOK_SECRET"),
      undefined,
      cryptoProvider,
    );
  } catch {
    return json({ error: "Signature invalide." }, 400);
  }

  const admin = adminClient();
  switch (event.type) {
    case "payment_intent.succeeded": {
      const intent = event.data.object as Stripe.PaymentIntent;
      const { data, error } = await admin.rpc("finalize_payment", { p_payment_intent: intent.id });
      if (error) throw error; // Stripe réessaiera automatiquement
      const result = data as { order_id: string | null; refund_cents: number; already_done?: boolean };
      if (!result.already_done && result.refund_cents > 0) {
        await stripe.refunds.create(
          { payment_intent: intent.id, amount: result.refund_cents },
          { idempotencyKey: `refund-${intent.id}` },
        );
      }
      break;
    }
    case "payment_intent.canceled": {
      const intent = event.data.object as Stripe.PaymentIntent;
      const { error } = await admin.rpc("cancel_payment", { p_payment_intent: intent.id });
      if (error) throw error;
      break;
    }
    default:
      // Un échec de carte n'annule pas la réservation : l'acheteur peut réessayer
      // avec une autre carte tant que la réservation (15 min) court.
      break;
  }
  return json({ received: true });
});
