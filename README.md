# forum-autonomie

Forum auto-hébergé + agents de veille IA, orientés maison autonome (électricité, eau, isolation). Budget 0 EUR : tout est auto-hébergé sur du matériel existant.

## Architecture (Proxmox VE, accès Tailscale uniquement)

| LXC | Hostname | IP | Rôle | Phase |
|-----|----------|----|------|-------|
| 106 | forum-autonomie | 192.168.0.106/24 (vmbr0) | Forum Flarum ou NodeBB + Nginx | P0 |
| 107 | veille-ia | 192.168.0.107/24 (vmbr0) | FreshRSS (P1) puis n8n (P2) | P1-P2 |

- LXC unprivileged, Debian 12, nesting activé, DNS fixes (8.8.8.8, 1.1.1.1) pour éviter l'écrasement par MagicDNS.
- Tailscale via l'hôte (pas de /dev/net/tun en LXC unprivileged).
- Pas de port ouvert vers Internet : bascule publique seulement si des membres réels se présentent.

## Phasage

- P0 : LXC 106 + forum (Flarum ou NodeBB), catégories selon le phasage rénovation (isolation capillaire / PAC-gaz / PV-batterie / eau de pluie / mesure et factures). Remplissage manuel 2 semaines.
- P1 : LXC 107 + FreshRSS, flux RSS techniques (constructeurs, sites BE/FR, communautés, low-tech, réglementation).
- P2 : n8n auto-hébergé dans le LXC 107, flux cron 6 h : RSS > filtrage > résumé (règles d'abord, IA ensuite) > post via API dans la bonne catégorie du forum.
- P3 : IA locale (Ollama, modèle 7B quantisé) seulement si le matériel tient.
- P4 : ouverture publique optionnelle (domaine, port forward, Caddy).

## Règles

- Toute donnée chiffrée publiée par un modèle est vérifiée à la source avant décision d'achat : le forum est une aide à décision, pas une décision.
- Les scripts de ce repo ne contiennent jamais de secrets : les clés vivent dans les fichiers .env locaux (chmod 600).
