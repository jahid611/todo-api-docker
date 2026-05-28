# TP2 – Journal de conteneurisation – todo-api

**Auteur :** Jahid Sayad  
**Date :** 2026-05-28  
**VM :** Ubuntu 22.04 LTS  
**Image publiée :** https://github.com/jahid611/todo-api-docker/pkgs/container/todo-api

---

## Étape 1 – Installation de Docker

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
sudo tee /etc/apt/sources.list.d/docker.list

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker $USER
newgrp docker

sudo systemctl disable --now todo-api nginx
```

```
$ docker version
Client: Docker Engine - Community
 Version: 26.1.4

$ docker compose version
Docker Compose version v2.27.1
```

```
$ docker run --rm hello-world
Hello from Docker!
```

---

## Étape 2 – Dockerfile multi-stage

```bash
docker build -t todo-api:1.0.0 .
```

Taille obtenue :

```
$ docker images todo-api
REPOSITORY   TAG       IMAGE ID       CREATED         SIZE
todo-api     1.0.0     a3f82c1e9d47   2 minutes ago   178MB
```

Comparaison avec le Dockerfile naïf (mono-stage) :

```bash
docker build -f Dockerfile.naive -t todo-api:naive .
```

```
$ docker images todo-api
REPOSITORY   TAG       IMAGE ID       CREATED         SIZE
todo-api     1.0.0     a3f82c1e9d47   3 minutes ago   178MB
todo-api     naive     9c1f4e2b8a31   1 minute ago    412MB
```

**Multi-stage : 178 MB vs mono-stage : 412 MB — gain de 57%**

Test local :

```bash
docker run --rm -p 3000:3000 -e JWT_SECRET=dev-secret todo-api:1.0.0
```

```
$ curl http://localhost:3000/health
{"status":"ok","uptime":8,"version":"1.0.0"}

$ curl -X POST http://localhost:3000/login -H "Content-Type: application/json" -d '{"username":"demo","password":"demo"}'
{"token":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."}
```

**Capture 1 – docker images + healthcheck**

```
$ docker images todo-api
REPOSITORY   TAG       IMAGE ID       CREATED         SIZE
todo-api     1.0.0     a3f82c1e9d47   4 minutes ago   178MB
todo-api     naive     9c1f4e2b8a31   2 minutes ago   412MB

$ docker inspect --format='{{json .State.Health.Status}}' $(docker ps -q --filter ancestor=todo-api:1.0.0)
"healthy"
```

---

## Étape 3 – Push sur GitHub Container Registry

```bash
echo $PAT | docker login ghcr.io -u jahid611 --password-stdin

docker tag todo-api:1.0.0 ghcr.io/jahid611/todo-api:1.0.0
docker tag todo-api:1.0.0 ghcr.io/jahid611/todo-api:latest

docker push ghcr.io/jahid611/todo-api:1.0.0
docker push ghcr.io/jahid611/todo-api:latest
```

```
$ docker push ghcr.io/jahid611/todo-api:1.0.0
The push refers to repository [ghcr.io/jahid611/todo-api]
1.0.0: digest: sha256:4c2a9f1b3e8d7c6a... size: 1573
```

Image visible sur : https://github.com/jahid611/todo-api-docker/pkgs/container/todo-api

---

## Étape 4 – Docker Compose

```bash
sudo mkdir -p /opt/todo-stack
sudo cp docker-compose.yml nginx.conf /opt/todo-stack/
cd /opt/todo-stack

JWT_SECRET=$(openssl rand -base64 48)
cat > .env <<EOF
GHCR_USER=jahid611
APP_VERSION=1.0.0
JWT_SECRET=${JWT_SECRET}
EOF
chmod 600 .env

docker compose up -d
```

```
$ docker compose ps
NAME                    IMAGE                              STATUS
todo-stack-app-1        ghcr.io/jahid611/todo-api:1.0.0   Up (healthy)
todo-stack-nginx-1      nginx:alpine                       Up
```

Test persistance (créer une todo, restart, vérifier) :

```bash
TOKEN=$(curl -s -X POST http://localhost/login -H "Content-Type: application/json" -d '{"username":"demo","password":"demo"}' | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
curl -X POST http://localhost/api/todos -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"title":"Persiste apres restart"}'
docker compose down
docker compose up -d
curl http://localhost/api/todos -H "Authorization: Bearer $TOKEN"
```

```
[{"id":1,"title":"Persiste apres restart","done":0}]
```

**Capture 2 – docker compose ps + persistance volume**

```
$ docker compose ps
NAME                    IMAGE                              COMMAND                  SERVICE   STATUS
todo-stack-app-1        ghcr.io/jahid611/todo-api:1.0.0   "node src/server.js"     app       Up (healthy)
todo-stack-nginx-1      nginx:alpine                       "/docker-entrypoint.…"   nginx     Up

$ docker volume ls | grep todo
local     todo-stack_todo-data

$ curl http://51.75.42.18/health
{"status":"ok","uptime":34,"version":"1.0.0"}
```

---

## Étape 5 – Script deploy.sh

Création de la version 1.0.1 (package.json version bumped à 1.0.1), build et push :

```bash
docker build -t todo-api:1.0.1 .
docker tag todo-api:1.0.1 ghcr.io/jahid611/todo-api:1.0.1
docker push ghcr.io/jahid611/todo-api:1.0.1
```

Déploiement :

```bash
cp deploy.sh /opt/todo-stack/
chmod +x /opt/todo-stack/deploy.sh
time /opt/todo-stack/deploy.sh 1.0.1
```

```
[2026-05-28 11:24:10] Deploy started: 1.0.0 -> 1.0.1
[2026-05-28 11:24:10] Backup SQLite -> /var/backups/todo-api/todos-20260528_112410.db
[2026-05-28 11:24:12] Pulling ghcr.io/jahid611/todo-api:1.0.1
[2026-05-28 11:24:18] Recreating app service
[2026-05-28 11:24:19] Smoke test (max 10 retries)
[2026-05-28 11:24:49] Deploy 1.0.1 OK (attempt 1)

real 0m39.4s
```

**Capture 3 – deploy.sh 1.0.1 (succès)**

```
$ curl http://51.75.42.18/health
{"status":"ok","uptime":5,"version":"1.0.1"}

$ cat /var/log/todo-deploy.log | tail -6
[2026-05-28 11:24:10] Deploy started: 1.0.0 -> 1.0.1
[2026-05-28 11:24:10] Backup SQLite -> /var/backups/todo-api/todos-20260528_112410.db
[2026-05-28 11:24:12] Pulling ghcr.io/jahid611/todo-api:1.0.1
[2026-05-28 11:24:18] Recreating app service
[2026-05-28 11:24:19] Smoke test (max 10 retries)
[2026-05-28 11:24:49] Deploy 1.0.1 OK (attempt 1)
```

---

## Étape 6 – Validation et mesures

### Test reboot

```bash
sudo reboot
```

Après reconnexion, sans aucune intervention :

```
$ curl http://51.75.42.18/health
{"status":"ok","uptime":23,"version":"1.0.1"}

$ curl http://51.75.42.18/api/todos -H "Authorization: Bearer $TOKEN"
[{"id":1,"title":"Persiste apres restart","done":0}]
```

Stack remontée automatiquement, données préservées.

### Comparaison tailles

| Image | Taille |
|---|---|
| todo-api:1.0.0 (multi-stage) | 178 MB |
| todo-api:naive (mono-stage) | 412 MB |

Gain : **-57%** grâce au multi-stage (outils de compilation absents du runtime).

### Test rollback

**Capture 4 – deploy.sh 9.9.9 (rollback automatique)**

```
$ /opt/todo-stack/deploy.sh 9.9.9
[2026-05-28 11:31:05] Deploy started: 1.0.1 -> 9.9.9
[2026-05-28 11:31:05] Backup SQLite -> /var/backups/todo-api/todos-20260528_113105.db
[2026-05-28 11:31:07] Pulling ghcr.io/jahid611/todo-api:9.9.9
Error response from daemon: manifest unknown
[2026-05-28 11:31:07] ERROR: Pull failed for version 9.9.9, aborting

$ curl http://51.75.42.18/health
{"status":"ok","uptime":412,"version":"1.0.1"}
```

L'ancienne version reste en place, les données sont intactes.
