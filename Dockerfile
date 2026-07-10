# escape=`
ARG WINDOWS_TAG=ltsc2022
FROM mcr.microsoft.com/windows/servercore:${WINDOWS_TAG}

SHELL ["powershell", "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"]

ARG BCCONTAINERHELPER_VERSION=latest

RUN $ErrorActionPreference = 'Stop'; `
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; `
    Install-PackageProvider NuGet -MinimumVersion 2.8.5.201 -Force; `
    Set-PSRepository PSGallery -InstallationPolicy Trusted; `
    if ($env:BCCONTAINERHELPER_VERSION -eq 'latest') { `
        Install-Module BcContainerHelper -Scope AllUsers -Force `
    } else { `
        Install-Module BcContainerHelper -RequiredVersion $env:BCCONTAINERHELPER_VERSION -Scope AllUsers -Force `
    }

WORKDIR C:\bootstrap
COPY bootstrap.ps1 C:\bootstrap\bootstrap.ps1

ENTRYPOINT ["powershell", "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "C:\\bootstrap\\bootstrap.ps1"]
