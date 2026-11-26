// Suppression du compte depuis l'app (exigée par l'App Store).
// Supprime l'utilisateur : profil, panier et swipes partent en cascade ;
// les commandes sont conservées (comptabilité) sans lien vers le compte.
import { adminClient, json, requireUser, serve } from "../_shared/clients.ts";

serve(async (req) => {
  const user = await requireUser(req);
  const admin = adminClient();

  // Libère d'éventuelles pièces réservées par un paiement en cours.
  await admin
    .from("garments")
    .update({ status: "available", reserved_by: null, reserved_until: null })
    .eq("status", "reserved")
    .eq("reserved_by", user.id);

  const { error } = await admin.auth.admin.deleteUser(user.id);
  if (error) throw error;
  return json({ deleted: true });
});
