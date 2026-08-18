/**
 * tests/app.test.js
 * Tests unitaires de l'application (Jest + Supertest).
 *
 * On teste les deux routes exposées par app.js :
 *  - GET /       : doit répondre 200 avec du HTML contenant "Demo Webapp"
 *  - GET /health : doit répondre 200 avec un JSON { status: "ok", ... }
 */

const request = require("supertest");
const app = require("../app");

describe("GET /", () => {
  it("répond avec un statut 200", async () => {
    const res = await request(app).get("/");
    expect(res.statusCode).toBe(200);
  });

  it("contient le texte 'Demo Webapp' dans la réponse", async () => {
    const res = await request(app).get("/");
    expect(res.text).toContain("Demo Webapp");
  });
});

describe("GET /health", () => {
  it("répond avec un statut 200", async () => {
    const res = await request(app).get("/health");
    expect(res.statusCode).toBe(200);
  });

  it("répond avec un JSON de statut 'ok'", async () => {
    const res = await request(app).get("/health");
    expect(res.body).toHaveProperty("status", "cassé");
  });
});
