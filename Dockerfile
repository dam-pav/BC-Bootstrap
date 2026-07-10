# escape=`
ARG WINDOWS_TAG=ltsc2022
FROM mcr.microsoft.com/windows/servercore:${WINDOWS_TAG}

SHELL ["powershell", "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"]

ARG BCCONTAINERHELPER_VERSION=latest
ARG DOCKER_VERSION=27.5.1
ARG SEVENZIP_VERSION=2602

RUN $ErrorActionPreference = 'Stop'; `
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; `
    Install-PackageProvider NuGet -MinimumVersion 2.8.5.201 -Force; `
    Set-PSRepository PSGallery -InstallationPolicy Trusted; `
    if ($env:BCCONTAINERHELPER_VERSION -eq 'latest') { `
        Install-Module BcContainerHelper -Scope AllUsers -Force `
    } else { `
        Install-Module BcContainerHelper -RequiredVersion $env:BCCONTAINERHELPER_VERSION -Scope AllUsers -Force `
    }; `
    Invoke-WebRequest "https://www.7-zip.org/a/7z$env:SEVENZIP_VERSION-x64.exe" -OutFile C:\7zip.exe; `
    Start-Process C:\7zip.exe -ArgumentList '/S' -Wait; `
    Remove-Item C:\7zip.exe -Force; `
    Invoke-WebRequest "https://download.docker.com/win/static/stable/x86_64/docker-$env:DOCKER_VERSION.zip" -OutFile C:\docker.zip; `
    Expand-Archive C:\docker.zip -DestinationPath C:\; `
    Move-Item C:\docker\docker.exe C:\Windows\System32\docker.exe; `
    Remove-Item C:\docker.zip, C:\docker -Recurse -Force

RUN Copy-Item 'C:\Program Files\7-Zip\7z.exe','C:\Program Files\7-Zip\7z.dll' C:\Windows\System32\

WORKDIR C:\bootstrap
COPY bootstrap.ps1 C:\bootstrap\bootstrap.ps1

ENTRYPOINT ["powershell", "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "C:\\bootstrap\\bootstrap.ps1"]
