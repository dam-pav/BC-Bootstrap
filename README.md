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

## Parameter sources

Parameters are merged in this order, with later sources overriding earlier ones:

1. JSON at `BCC_PARAMETERS_FILE`
2. JSON in `BCC_PARAMETERS_JSON`
3. every environment variable named `BCC_PARAM_<parameterName>`

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

Or add arbitrary `BCC_PARAM_*` variables directly to `.env`; the service's
`env_file` passes them through without requiring a Compose-file change.

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
