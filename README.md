`himmelblau-dev` is an R&D environment for
[himmelblau](https://github.com/himmelblau-idm/himmelblau).

# Development

The project is based on `Makefile` orchestration, and for the time being
requires Debian user space in order to be usable.

In order to list of all the available commands and their descriptions, run:

    make help

> **Note**: The build process (`make build-image`) requires `sudo` privileges
  for tasks like disk partitioning and bootstrapping Debian.

1.  **Dependencies**

    Install the required packages for building the VM image and running the
    QEMU scripts.

    ```bash
    sudo apt install make guestfish debootstrap qemu-utils ovmf swtpm-tools jq curl libguestfs-tools virt-viewer
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

    The run target starts the VM and automatically opens a SPICE viewer.

    ```bash
    make run
    ```

    To use bridged networking instead of user-mode networking:

    ```bash
    make run BRIDGE=1
    ```

# Himmelblau

Although the official *Intune app* provided by Microsoft offers some support for
Linux clients, the coverage is weaker than on other supported platforms. The
*Linux client profile* that Microsoft provides for Azure and Intune offers only
the basic access control.

In order to circumvent the limitations caused by the lack of proper device
management and authorization policies for Linux clients, Himmelblau takes a
different approach.

Himmeblau interoperates with the Azure cloud by implementing the *Windows client
profile*.

## `himmelblau.conf`

### `apply_policy`

`apply_policy` enables Intune policy enforcement locally.
Himmelblau downloads Intune compliance policies and enforces them during login.
For the time being, compliance results are not yet reported back to the Azure
cloud.,

# Official Documentation

For more in-depth information about Himmelblau, its architecture, and advanced
troubleshooting, please refer to the official documentation:

* [**Configuration Reference**](https://himmelblau-idm.org/docs/configuration/):
  A detailed guide to the Himmeblau configuration.
* [**Architecture Overview**](https://himmelblau-idm.org/docs/architecture/):
  Core components and architecture.
* [**Troubleshooting Guide**](https://himmelblau-idm.org/docs/troubleshooting/):
  A useful troubleshooting guide.

Copyright (c) 2025 Opinsys Oy
