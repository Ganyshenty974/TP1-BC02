# Image légère basée sur Node.js
FROM node:20-alpine

WORKDIR /app

# On copie d'abord uniquement les fichiers de dépendances pour
# profiter du cache Docker (rebuild plus rapide si le code change
# mais pas les dépendances).
COPY package.json package-lock.json* ./
RUN npm install --omit=dev

# Puis le reste du code applicatif
COPY . .

# Argument fourni au run pour rendre le port paramétrable
ENV PORT=3000
EXPOSE 3000

CMD ["node", "server.js"]
