# bug-free-robot

## Debian Setup Script

**Run it on a Fresh Debian Install.**

```bash
# Basic (everything except Docker)
curl -fsSL https://raw.githubusercontent.com/psycho-daisies/bug-free-robot/main/debian-bootstrap.sh | bash

# Example: skip KDE, include Docker
INSTALL_KDE=false INSTALL_DOCKER=true \
curl -fsSL https://raw.githubusercontent.com/psycho-daisies/bug-free-robot/main/debian-bootstrap.sh | bash

```


## Docker Setup Script

**Install Docker & Docker Compose.**
```bash
curl -fsSL https://raw.githubusercontent.com/psycho-daisies/bug-free-robot/main/docker-setup.sh | bash
# then immediately (no logout needed):
newgrp docker
docker run --rm hello-world
```
