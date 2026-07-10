# BcContainerHelper bootstrap with Docker Compose

This project runs BcContainerHelper in a Windows helper container and gives it
access to the host Windows Docker engine. The helper then creates the Business
Central container. This is sometimes called Docker-in-Docker, but technically it
is Docker-outside-of-Docker: the Docker named pipe is shared and there is only
one daemon.

## Requirements

- Windows 10/11 or Windows Server with Docker configured for **Windows containers**
- A host/container OS match (the default image is LTSC 2022)
- Docker Compose v2
- Enough memory and disk for a Business Central container

## Configure and run

1. Copy `.env.example` to `.env`.
2. Create the absolute directory in `HOST_FILES_PATH` (default
   `C:\BcBootstrapFiles`) and put input files such as the license there.
3. Edit `config/parameters.json`.
4. Run:

   ```powershell
   docker compose build
   docker compose run --rm bc-bootstrap
   ```

Use `docker compose up --build --abort-on-container-exit` if preferred. The
bootstrap is intentionally a one-shot container; the Business Central container
continues under the host Docker engine after the helper exits.

## Docker networking

The bootstrap helper and the Business Central container have independent
network settings:

- `BOOTSTRAP_NETWORK_NAME` is the existing network to which Compose attaches
  the one-shot helper. The default is Docker's `nat` network.
- `BCC_NETWORK_NAME` is passed to `New-BcContainer -network` and controls the
  network of the created Business Central container.

They do not need to use the same network or network driver. The helper only
needs routed access to the BC container's WinRM HTTPS endpoint and a way to
resolve its name. When `BCC_CONTAINER_IP` is set, the bootstrap adds a temporary
name-to-address mapping to its own hosts file before running New-BcContainer.

For a NAT deployment, no additional file is needed:

```powershell
docker compose run --rm bc-bootstrap
```

For a transparent BC deployment, create the target network once on the Docker
host. The helper can remain on `nat`:

```powershell
docker network create -d transparent `
  --subnet 192.168.10.0/24 `
  --gateway 192.168.10.1 `
  bc-transparent
```

Set these values in `.env` (using addresses appropriate for that subnet):

```dotenv
BOOTSTRAP_NETWORK_NAME=nat
BCC_NETWORK_NAME=bc-transparent
BCC_CONTAINER_IP=192.168.10.41
BCC_HOST_IP=192.168.10.10
```

Then deploy normally:

```powershell
docker compose up --build --abort-on-container-exit
```

`BCC_CONTAINER_IP` is passed to `New-BcContainer -IP`. The bootstrap also adds
that address and `BCC_CONTAINER_NAME` to its own hosts file before creation,
which makes the post-create WinRM session independent of DNS propagation.

The host routing and firewall must allow the NAT-attached helper to reach the
transparent address over WinRM HTTPS (normally TCP 5986). If that route is not
available in a particular environment, attach the helper to a network that can
reach the target; matching the transparent driver is not otherwise required.

For durable access from other machines, register an A record for the BC
container name (or the value supplied through the BcContainerHelper
`PublicDnsName` parameter) at `BCC_CONTAINER_IP`. Reserve or exclude that static
address in DHCP/IPAM.

BcContainerHelper's related parameters remain available through
`config/parameters.json`, `BCC_PARAMETERS_JSON`, or `BCC_PARAM_*`: `dns`,
`hostIP`, `macAddress`, `PublicDnsName`, `PublishPorts`, and `updateHosts`.
Explicit parameter values override the dedicated network environment defaults.

## Parameter sources

Parameters are merged in this order, with later sources overriding earlier ones:

1. JSON from `BCC_PARAMETERS_FILENAME` in the mounted config directory
2. JSON in `BCC_PARAMETERS_JSON`
3. every environment variable named `BCC_PARAM_<parameterName>`

`BCC_CONTAINER_NAME` provides a dedicated override for `containerName`.

The bootstrap first checks the mounted config directory for both required files.
This uses files cloned with the stack when the Portainer installation provides
the complete repository, without requiring GitHub variables. If either file is
missing (as can happen with Portainer CE), only the missing files are downloaded
anonymously from the public `dam-pav/bc-bootstrap` repository's `config/`
directory into `HOST_CONFIG_PATH`.

This allows any parameter exposed by the installed BcContainerHelper command.
Unknown names fail early. JSON values retain their types, so booleans, arrays,
objects, numbers, and strings are supported. For example:

```powershell
$env:BCC_PARAMETERS_JSON = '{"includeAL":true,"memoryLimit":"12G"}'
docker compose run --rm bc-bootstrap
```

For a moving current artifact, set `artifactUrl` to
`latest:<type>:<country>`, for example `latest:sandbox:w1`. The bootstrap
resolves it with `Get-BcArtifactUrl -select Latest` immediately before creating
the container.

For arbitrary `BCC_PARAM_*` values, either add an explicit mapping under the
service's `environment` section or place them in `BCC_PARAMETERS_JSON`. Compose
uses a local `.env` for `${...}` interpolation, while Portainer can provide the
same values through its stack environment.

`Credential` may be supplied as a JSON object:

```json
"Credential": { "username": "admin", "password": "secret" }
```

Prefer `BCC_CREDENTIAL_USERNAME` and `BCC_CREDENTIAL_PASSWORD` (or Compose
secrets in a hardened deployment) so credentials do not live in the parameters
file. Set `BCC_DRY_RUN=true` to validate names and parsing without creating a BC
container.

## Files and paths

The config directory is mounted read-only at `C:\bootstrap\config`. The path in
`HOST_FILES_PATH` is mounted at the **same absolute path** in the helper. This is
important: BcContainerHelper and the host Docker daemon must agree on file paths,
especially when values are also used in `additionalParameters` volume mappings.

The helper and artifact caches are bind-mounted at the same absolute paths on
the host and helper container. This is required because the host Docker daemon
must be able to mount BCContainerHelper's generated extension and artifact
files into the Business Central container. The Docker named pipe grants the
helper full control over the host Docker daemon; only run trusted images and
parameter files.
