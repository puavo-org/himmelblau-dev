Copyright (c) 2025 Opinsys Oy

# Overview

## Intune App

Although the official app provided by Microsoft offers some support for Linux
clients, the coverage is weaker than on other supported platforms. The *Linux
profile* that Microsoft provides for Azure and Intune offers only the basic
access control.

The architectural breakdown for reference:

* `intuned.service`:
  * Policy checks (e.g., OS version, disk encryption).
  * Report the device status back to Microsoft cloud.

* `microsoft-identity-broker.service`:
  * Registers the device with Microsoft Entra ID.
  * Manages Kerberos tokens.

## Himmelblau

In order to circumvent the limitations caused by the lack of proper device
management and authorization policies for Linux clients, Himmelblau takes a
different approach.

Himmeblau interoperates with the Azure cloud by providing a Windows client
interoperatibility layer. By practical means Himmeblau provides tools and
services for a Linux machine to appear as a *Windows client*.

## linux-entra-sso

`linux-entra-sso` is a Firefox extension, providing an alternative on using
Edge browser to access services in an Azure based IT infrastructure. It
integrates both with Intune App and Himmeblau.

# Development

## Build and Run

The project is based on `Makefile` orchestration, and for the time being
requires Debian user space in order to be usable.

> **Note**: The build process (`make build-image`) requires `sudo` privileges
  for tasks like disk partitioning and bootstrapping Debian.

1.  **Dependencies**

    Install the required packages for building the VM image and running the
    QEMU scripts.

    ```bash
    sudo apt install make guestfish debootstrap qemu-utils ovmf swtpm-tools jq curl libguestfs-tools
    ```

2.  **Environment**

    Copy the example environment file and fill in your Azure tenant details.
    You can also enable advanced Himmelblau features here.

    ```bash
    cp .env.example .env
    nano .env
    ```

3.  **Building**

    ```bash
    make build
    ```

4.  **Run the Virtual Machine**

    ```bash
    make run
    ```

## Makefile Targets

In order to list of all the available commands and their descriptions, run:

    make help

## Official Documentation

For more in-depth information about Himmelblau, its architecture, and advanced
troubleshooting, please refer to the official documentation:

* [**Configuration Reference**](https://himmelblau-idm.org/docs/configuration/):
  A detailed guide to the Himmeblau configuration.
* [**Architecture Overview**](https://himmelblau-idm.org/docs/architecture/):
  Core components and architecture.
* [**Troubleshooting Guide**](https://himmelblau-idm.org/docs/troubleshooting/):
  A useful troubleshooting guide.
