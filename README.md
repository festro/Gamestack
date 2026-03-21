# GameStack

Portable Docker Compose stack running on KDE Neon / any Linux + Docker host.

## Services
- **AMP** - Game server management panel (V Rising + others)
- **Wolf** - Headless GPU game streaming server (Moonlight compatible)

## URLs
- AMP Web UI: http://HOST_IP:8080
- Wolf: http://HOST_IP:47989

## First Run
```bash
cd /home/festro33/gamestack
./setup.sh
```

## Move to Another Machine
```bash
# On current machine
tar -czf gamestack.tar.gz /home/festro33/gamestack/

# On new machine
tar -xzf gamestack.tar.gz
cd gamestack
./setup.sh
```

## Ports
| Service | Port | Protocol |
|---------|------|----------|
| AMP Web UI | 8080 | TCP |
| V Rising Game | 9876 | UDP |
| V Rising Query | 9877 | UDP |
| Wolf Stream | 47984-48010 | TCP/UDP |

## Notes
- AMP MAC address is fixed in .env to prevent licence deactivation
- All data lives in ampdata/ and wolf-config/
- .env contains credentials - never commit to git
