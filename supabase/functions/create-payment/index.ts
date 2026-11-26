// Prépare un paiement : réserve les pièces (15 min) puis crée un PaymentIntent
// Stripe du montant exact calculé par la base. L'app présente ensuite la
// feuille de paiement Stripe (carte / Apple Pay) avec le client_secret.
import { adminClient, HttpError, json, requireUser, serve, stripeClient } from "../_shared/clients.ts";

type DeliveryMethod = "home" | "relayPoint";

interface CreatePaymentRequest {
  garment_ids: string[];
  delivery_method: DeliveryMethod;
}

interface Reservation {
  reserved: string[];
  unavailable: string[];
  subtotal_cents: number;
  shipping_cents: number;
  service_fee_cents: number;
  total_cents: number;
}

serve(async (req) => {
  const user = await requireUser(req);
  const body = (await req.json()) as Partial<CreatePaymentRequest>;
  const garmentIds = Array.isArray(body.garment_ids) ? body.garment_ids.filter((id) => typeof id === "string") : [];
  const method: DeliveryMethod = body.delivery_method === "relayPoint" ? "relayPoint" : "home";
  if (garmentIds.length === 0 || garmentIds.length > 50) {
    throw new HttpError(400, "Panier invalide.");
  }

  const admin = adminClient();
  const { data: profile, error: profileError } = await admin
    .from("profiles")
    .select("first_name, last_name, address_line1, address_line2, postal_code, city, country, relay_point")
    .eq("id", user.id)
    .single();
  if (profileError || !profile) throw new HttpError(400, "Profil introuvable.");
  if (!profile.address_line1 || !profile.postal_code || !profile.city) {
    throw new HttpError(400, "Complète ton adresse de livraison dans ton profil.");
  }
  if (method === "relayPoint" && !profile.relay_point) {
    throw new HttpError(400, "Choisis un point relais dans ton profil.");
  }

  const { data: reservationData, error: reserveError } = await admin.rpc("reserve_garments", {
    p_buyer: user.id,
    p_garment_ids: garmentIds,
    p_method: method,
  });
  if (reserveError) throw reserveError;
  const reservation = reservationData as Reservation;

  if (reservation.reserved.length === 0) {
    return json({ payment_intent_id: null, client_secret: null, ...reservation });
  }

  const buyerName = `${profile.first_name} ${profile.last_name}`.trim();
  const stripe = stripeClient();
  let paymentIntent;
  try {
    paymentIntent = await stripe.paymentIntents.create({
      amount: reservation.total_cents,
      currency: "eur",
      allowed_payment_method_types: ["card"], // Apple Pay passe par « card »
      description: `StyleMatch – ${reservation.reserved.length} pièce(s)`,
      receipt_email: user.email ?? undefined,
      metadata: { buyer_id: user.id, garment_ids: reservation.reserved.join(",") },
    });
  } catch (error) {
    await admin.rpc("release_garments", { p_buyer: user.id, p_garment_ids: reservation.reserved });
    throw error;
  }

  const { error: insertError } = await admin.from("payments").insert({
    payment_intent: paymentIntent.id,
    buyer_id: user.id,
    garment_ids: reservation.reserved,
    amount_cents: reservation.total_cents,
    delivery_method: method,
    shipping_address: {
      line1: profile.address_line1,
      line2: profile.address_line2,
      postal_code: profile.postal_code,
      city: profile.city,
      country: profile.country,
    },
    relay_point: method === "relayPoint" ? profile.relay_point : "",
    buyer_name: buyerName,
  });
  if (insertError) {
    await stripe.paymentIntents.cancel(paymentIntent.id);
    await admin.rpc("release_garments", { p_buyer: user.id, p_garment_ids: reservation.reserved });
    throw insertError;
  }

  return json({
    payment_intent_id: paymentIntent.id,
    client_secret: paymentIntent.client_secret,
    ...reservation,
  });
});
