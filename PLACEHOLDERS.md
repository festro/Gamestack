# Placeholder Map

Generated 2026-08-02 against commit `fd63f9d`. Every generic placeholder in the
tracked tree, with the exact file and line where your real value belongs.
`configure.sh` fills most of these automatically; `sterilize.sh` resets them all
back to the placeholders listed here. (`sterilize.sh` itself is excluded from this
map — its replacement expressions necessarily mention these tokens.)

## Network

### `YOUR_HOST_IP`
LAN IP of the machine running GameStack (the docker host).

| File | Line |
|------|------|
| SETUP_CHECKLIST.md | 95 |
| SETUP_CHECKLIST.md | 111 |
| SETUP_CHECKLIST.md | 112 |
| SETUP_CHECKLIST.md | 114 |
| SETUP_CHECKLIST.md | 117 |
| SETUP_CHECKLIST.md | 120 |
| SETUP_CHECKLIST.md | 121 |
| SETUP_CHECKLIST.md | 122 |
| build.js | 64 |
| build.js | 85 |
| build.js | 91 |
| build.js | 92 |
| build.js | 94 |
| build.js | 119 |
| build.js | 133 |
| build.js | 134 |
| build.js | 144 |
| build.js | 145 |
| build.js | 161 |
| build.js | 176 |
| build.js | 182 |
| build.js | 211 |
| configure.sh | 173 |
| configure.sh | 193 |
| configure.sh | 215 |
| configure.sh | 221 |
| docker-compose.yml | 142 |
| portal/html/index.html | 1102 |
| portal/html/index.html | 1103 |

### `YOUR_PUBLIC_IP`
WAN/public IP of your network, for port-forwarded external access.

| File | Line |
|------|------|
| SETUP_CHECKLIST.md | 96 |
| SETUP_CHECKLIST.md | 115 |
| SETUP_CHECKLIST.md | 123 |
| build.js | 116 |
| build.js | 146 |
| build.js | 178 |
| build.js | 213 |
| configure.sh | 174 |
| configure.sh | 194 |
| configure.sh | 215 |
| configure.sh | 221 |
| portal/html/index.html | 1012 |
| portal/html/index.html | 1119 |

### `YOUR_ROUTER_IP`
LAN IP of your router/gateway.

| File | Line |
|------|------|
| SETUP_CHECKLIST.md | 97 |
| SETUP_CHECKLIST.md | 119 |
| configure.sh | 175 |
| configure.sh | 195 |
| configure.sh | 215 |
| configure.sh | 221 |

### `YOUR_UPSTREAM_ROUTER_IP`
Upstream router IP if you are behind double NAT.

| File | Line |
|------|------|
| SETUP_CHECKLIST.md | 98 |
| SETUP_CHECKLIST.md | 119 |
| configure.sh | 176 |
| configure.sh | 196 |
| configure.sh | 215 |
| configure.sh | 221 |

### `YOUR_MODEM_IP`
Modem admin IP, if applicable.

| File | Line |
|------|------|
| SETUP_CHECKLIST.md | 99 |
| SETUP_CHECKLIST.md | 118 |
| configure.sh | 177 |
| configure.sh | 197 |
| configure.sh | 215 |
| configure.sh | 221 |

## Identity

### `your-hostname`
Hostname of the GameStack host machine.

| File | Line |
|------|------|
| SETUP_CHECKLIST.md | 88 |
| SETUP_CHECKLIST.md | 94 |
| SETUP_CHECKLIST.md | 110 |
| build.js | 65 |
| configure.sh | 172 |
| configure.sh | 192 |
| configure.sh | 215 |
| configure.sh | 221 |
| portal/html/index.html | 886 |

### `your-username`
Linux username that owns and runs the stack.

| File | Line |
|------|------|
| SETUP_CHECKLIST.md | 93 |
| SETUP_CHECKLIST.md | 109 |
| build.js | 28 |
| build.js | 44 |
| build.js | 65 |
| build.js | 131 |
| build.js | 132 |
| configure.sh | 170 |
| configure.sh | 190 |
| configure.sh | 215 |
| configure.sh | 221 |

### `game.yourdomain.com`
Game subdomain (GAME_SUBDOMAIN + DOMAIN) pointing at your public IP.

| File | Line |
|------|------|
| SETUP_CHECKLIST.md | 85 |
| SETUP_CHECKLIST.md | 113 |
| SETUP_CHECKLIST.md | 123 |
| SETUP_CHECKLIST.md | 125 |
| build.js | 146 |
| build.js | 147 |
| build.js | 178 |
| build.js | 184 |
| build.js | 194 |
| configure.sh | 181 |
| configure.sh | 199 |
| portal/html/index.html | 975 |
| portal/html/index.html | 1119 |
| portal/html/index.html | 1130 |

### `yourdomain.com`
Your personal domain (bare, non-game references).

| File | Line |
|------|------|
| SETUP_CHECKLIST.md | 84 |
| SETUP_CHECKLIST.md | 124 |
| build.js | 46 |
| build.js | 148 |
| build.js | 179 |
| configure.sh | 182 |
| configure.sh | 200 |
| portal/html/index.html | 1120 |

## AMP credentials

### `your_amp_username`
AMP panel username.

| File | Line |
|------|------|
| .env.example | 15 |
| SETUP_CHECKLIST.md | 23 |
| configure.sh | 158 |
| configure.sh | 215 |
| configure.sh | 221 |
| portal/html/index.html | 874 |

### `your_amp_password`
AMP panel password.

| File | Line |
|------|------|
| .env.example | 16 |
| SETUP_CHECKLIST.md | 24 |
| configure.sh | 159 |
| configure.sh | 215 |
| configure.sh | 221 |

### `your_amp_licence_key`
CubeCoders AMP licence key.

| File | Line |
|------|------|
| .env.example | 17 |
| SETUP_CHECKLIST.md | 25 |
| configure.sh | 160 |

### `02:42:xx:xx:xx:xx`
Fixed MAC address for the AMP container. AMP licences bind to the MAC — pick one, set it once, never change it.

| File | Line |
|------|------|
| .env.example | 21 |
| SETUP_CHECKLIST.md | 26 |
| configure.sh | 161 |

