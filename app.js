/**
 * app.js
 * Définition de l'application Express, séparée du démarrage du serveur
 * (voir server.js). Cette séparation permet de tester les routes avec
 * Jest + Supertest sans avoir besoin d'ouvrir un vrai port réseau.
 *
 * Deux routes :
 *  - GET /        : page d'accueil, prouve que l'app tourne
 *  - GET /health   : endpoint de health check, utilisé par le script
 *                    de déploiement (TP1) et par le pipeline CI (TP2)
 *                    pour valider que l'application répond correctement.
 */

const express = require("express");
const app = express();

const APP_VERSION = process.env.APP_VERSION || "1.0.0";

app.get("/", (req, res) => {
  res.send(
    `<h1>Demo Webapp</h1><p>Version ${APP_VERSION}</p><p>Statut : en ligne ✅</p>`
  );
});

app.get("/health", (req, res) => {
  res.status(200).json({ status: "ok", version: APP_VERSION });
});

module.exports = app;
