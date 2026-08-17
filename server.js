/**
 * server.js
 * Application de démonstration minimale (Express).
 *
 * Deux routes :
 *  - GET /        : page d'accueil, prouve que l'app tourne
 *  - GET /health   : endpoint de health check, utilisé par le script
 *                    de déploiement pour valider que le conteneur
 *                    répond correctement après démarrage.
 *
 * Le port est lu depuis la variable d'environnement PORT (avec une
 * valeur par défaut), pour rester paramétrable sans modifier le code.
 */

const express = require("express");
const app = express();

const PORT = process.env.PORT || 3000;
const APP_VERSION = process.env.APP_VERSION || "1.0.0";

app.get("/", (req, res) => {
  res.send(
    `<h1>Demo Webapp</h1><p>Version ${APP_VERSION}</p><p>Statut : en ligne ✅</p>`
  );
});

// Endpoint dédié au health check : renvoie un JSON simple avec
// un code HTTP 200 si tout va bien. C'est cette route que le
// script deploy.sh interrogera pour valider le déploiement.
app.get("/health", (req, res) => {
  res.status(200).json({ status: "ok", version: APP_VERSION });
});

app.listen(PORT, () => {
  console.log(`Demo webapp (v${APP_VERSION}) à l'écoute sur le port ${PORT}`);
});
