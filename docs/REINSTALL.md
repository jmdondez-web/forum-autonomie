# Forum-autonomie — Documentation de réinstallation

## Postulat de départ

- Hôte Proxmox VE (Proxmox), en root, avec Tailscale actif (machine nommée `proxmox`).
- Tailnet : `tail45201a` ; domaine servi : `proxmox.tail45201a.ts.net`.
- Stockage LXC : `local-lvm` ; ponts : vmbr0 (LAN 192.168.0.0/24) ; passerelle 192.168.0.1.
- Repo GitHub : `jmdondez-web/forum-autonomie`, branche `main`. Tout ce document repose sur ses scripts.
- Les conteneurs sont UNPRIVILEGED avec nesting=1 (requis pour systemd).

## Architecture cible

| Élément | Conteneur | IP locale | Service | Accès Tailscale |
|---|---|---|---|---|
| Forum NodeBB 3.x | LXC 106 (forum-autonomie) | 192.168.0.106 | nodebb.service (systemd), port 4567, Redis | https://proxmox.tail45201a.ts.net/ (443) |
| Veille FreshRSS | LXC 107 (veille-ia) | 192.168.0.107 | nginx + php-fpm, port 80, SQLite | https://proxmox.tail45201a.ts.net:8443/ |

Tailscale tourne uniquement sur l'hôte. Les LXC n'ont pas de Tailscale. Le 443 et le 8443 sont servis par `tailscale serve` sur l'hôte, proxy vers les LXC.

## Données à sauvegarder

LXC 106 (NodeBB) :
- Redis : `/var/lib/redis/dump.rdb` (données des messages, comptes, catégories). Sur l'hôte dans l'ordre : `pct exec 106 -- systemctl stop nodebb` puis `pct exec 106 -- cat /var/lib/redis/dump.rdb > nodebb-dump.rdb` (le service nodebb doit être relancé ensuite).
- Fichiers téléversés : `pct exec 106 -- tar czf - /opt/nodebb/uploads` (tar czf nodebb-uplinks.tar.gz avant copie).
- Config : `pct exec 106 -- cat /opt/nodebb/config.json`.

LXC 107 (FreshRSS) :
- Tout est dans `/usr/share/FreshRSS/data` : base SQLite, config (`config.php`), utilisateurs et feeds,`users` et OPML.
- Sauvegarde : `pct exec 107 -- tar czf - /usr/share/FreshRSS/data` (penser à sauvegarder ce tar.gz, ex. monthly copie vers un autre stockage de l'hôte).
- Également utile : export OPML régulier dès l'interface FreshRSS (Administration → Import/Export).

Mots de passe : jamais dans le repo. Gestionnaire de mots de passe.

## Réinstallation complète (les deux LXC perdus)

Durée : ~30 minutes, deux étapes interactives (setup NodeBB, installeur web FreshRSS).

### 1. Créer les conteneurs (hôte)

```
cd ~
git clone https://github.com/jmdondez-web/forum-autonomie.git
bash forum-autonomie/deploy/create-lxc.sh
```
Crée 106 (forum-autonomie) et 107 (veille-ia), Debian 12, IP fixes .106/.107, démarrés.

### 2. Forum NodeBB (LXC 106)

```
pct exec 106 -- bash -c 'apt-get update -qq && apt-get install -y -qq curl git'
pct exec 106 -- bash -c 'curl -fsSL -o /tmp/setup.sh https://raw.githubusercontent.com/jmdondez-web/forum-autonomie/main/deploy/setup-nodebb-106.sh && bash /tmp/setup.sh'
```
Puis setup interactif :
```
pct exec 106
cd /opt/nodebb && ./nodebb setup
```
Réponses : URL `http://192.168.0.106:4567` (corrigée plus tard), host `0.0.0.0`, Redis par défaut, puis créer le compte admin. Sortir du conteneur : `exit`.

Service systemd (reprend la main à chaque démarrage) :
```
pct exec 106 -- bash -c 'curl -fsSL -o /etc/systemd/system/nodebb.service https://raw.githubusercontent.com/jmdondez-web/forum-autonomie/main/deploy/nodebb.service'
pct exec 106 -- systemctl daemon-reload
pct exec 106 -- systemctl enable nodebb
pct exec 106 -- systemctl start nodebb
pct exec 106 -- systemctl is-active nodebb    # attendu : active
```

Jamais `./nodebb start` à la main : ça capture la console et fait bloquer pct enter / exit. Toujours systemctl.

Restauration des données (si sauvegarde existante) :
```
pct exec 106 -- systemctl stop nodebb
# restaurer dump.rdb dans /var/lib/redis/dump.rdb et uploads dans /opt/nodebb/uploads
pct exec 106 -- bash -c 'chown redis:redis /var/lib/redis/dump.rdb && systemctl restart redis-server && systemctl start nodebb'
```

### 3. FreshRSS (LXC 107)

```
pct exec 107 -- bash -c 'apt-get update -qq && apt-get install -y -qq curl'
pct exec 107 -- bash -c 'curl -fsSL -o /tmp/setup.sh https://raw.githubusercontent.com/jmdondez-web/forum-autonomie/main/deploy/setup-freshrss-107.sh && bash /tmp/setup.sh'
```
Fin attendue : `== Done ==`.

Restauration (si sauvegarde) : décompresser le tar.gz de `data` dans `/usr/share/FreshRSS/data`, puis `chown -R www-data:www-data /usr/share/FreshRSS/data`. Sinon, installeur web, étape après l'accès (voir 5) : environnement OK, base SQLite, créer le compte admin, puis charger l'OPML exporté.

### 4. Accès Tailscale (hôte)

```
tailscale serve --bg --https=443 http://192.168.0.106:4567
tailscale serve --bg --https=8443 http://192.168.0.107:80
tailscale serve status
```

### 5. URL de base NodeBB

```
pct exec 106 -- bash -c 'sed -i "s|http://192.168.0.106:4567|https://proxmox.tail45201a.ts.net|" /opt/nodebb/config.json && systemctl restart nodebb'
```

## Vérifications finales

- `pct exec 106 -- systemctl is-active nodebb` → active
- `pct exec 107 -- systemctl is-active nginx` → active
- `tailscale serve status` → deux proxys listés (443/8443)
- Forum : `https://proxmox.tail45201a.ts.net/` affiche NodeBB et la connexion admin fonctionne
- FreshRSS : `https://proxmox.tail45201a.ts.net:8443/` affiche FreshRSS et le chargement des flux fonctionne
- Après `pct reboot` de l'hôte : les deux services relancés automatiquement (systemd enable) et `tailscale serve` persistant (--bg)

## Réinstallation partielle

- Forum seul : créer 106 (`bash create-lxc.sh 106`), puis section 2 + services serve + URL.
- FreshRSS seul : créer 107 (`bash create-lxc.sh 107`), puis section 3 + serve 8443.
- Recharge après mise à jour scripts : retélécharger (raw.githubusercontent sert avec quelques minutes de délai CDN ; ajouter `?t=$(date +%s)` à l'URL pour forcer).
-tailscale serve réinitialisé : réexécuter les deux serve; le flag `--bg` persiste les règles.

## Pièges connus (constatés le 21/11/2026)

- Copier-coller des commandes depuis l'application mobile insère des caractères invisibles (rendu `000` sur la vérification curl). Taper les commandes à la main.
- `curl` n'est pas dans l'image Debian minimale des LXC : l'installer avant tout script.
- `git` dans le LXC 107 : si `detected dubious ownership` sur /usr/share/FreshRSS → `git config --global --add safe.directory /usr/share/FreshRSS`.
- Ne jamais lancer NodeBB en avant-plan (`./nodebb start` manuel) : console capturée, Ctrl+C parfois sans effet, `exit` bloque.
