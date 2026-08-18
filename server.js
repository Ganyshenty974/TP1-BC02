/**
 * server.js
 * Point d'entrée qui démarre le serveur HTTP à partir de l'application
 * définie dans app.js. Séparé de app.js pour permettre les tests
 * automatisés (Jest) sans ouvrir de port réseau.
 *
 * Le port est lu depuis la variable d'environnement PORT (avec une
 * valeur par défaut), pour rester paramétrable sans modifier le code.
 */

const app = require("./app");

const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log(`Demo webapp à l'écoute sur le port ${PORT}`);
});
