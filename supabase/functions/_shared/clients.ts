import { createClient, type SupabaseClient, type User } from "npm:@supabase/supabase-js@2.117.3";
import Stripe from "npm:stripe@23.0.0";

export function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Variable d'environnement manquante : ${name}`);
  return value;
}

/** Client avec la clé service_role : contourne la RLS, réservé au serveur. */
export function adminClient(): SupabaseClient {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export function stripeClient(): Stripe {
  return new Stripe(env("STRIPE_SECRET_KEY"), {
    httpClient: Stripe.createFetchHttpClient(),
  });
}

/** Utilisateur authentifié à partir du jeton envoyé par l'app. */
export async function requireUser(req: Request): Promise<User> {
  const authorization = req.headers.get("Authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "");
  if (!token) throw new HttpError(401, "Connexion requise.");
  const { data, error } = await adminClient().auth.getUser(token);
  if (error || !data.user) throw new HttpError(401, "Session expirée, reconnecte-toi.");
  return data.user;
}

export class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** Enveloppe un handler : erreurs => réponse JSON { error } lisible par l'app. */
export function serve(handler: (req: Request) => Promise<Response>): void {
  Deno.serve(async (req) => {
    if (req.method !== "POST") return json({ error: "Méthode non autorisée." }, 405);
    try {
      return await handler(req);
    } catch (error) {
      if (error instanceof HttpError) return json({ error: error.message }, error.status);
      console.error(error);
      return json({ error: "Erreur serveur, réessaie dans un instant." }, 500);
    }
  });
}
