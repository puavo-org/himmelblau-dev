`himmelblau-dev` is an R&D environment for
[himmelblau](https://github.com/himmelblau-idm/himmelblau).

# Development

The project is based on `Makefile` orchestration, and for the time being
requires Debian user space in order to be usable.

In order to list of all the available commands and their descriptions, run:

    make help

> **Note**: The build process (`make build`) requires `sudo` privileges
> for tasks like disk partitioning and bootstrapping Debian.

1.  **Dependencies**

    Install the required packages for building the VM image and managing it
    with libvirt.

    ```bash
    sudo apt install \
      make guestfish debootstrap qemu-utils ovmf swtpm-tools jq curl \
      libguestfs-tools virt-viewer virtinst libvirt-daemon-system libvirt-clients \
      python3
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

    This produces a QCOW2 disk image and UEFI firmware blobs in the `build/`
    directory.

4.  **Install libvirt domain**

    Define or update a libvirt VM using the built image:

    ```bash
    make install
    ```

    This will generate `build/himmelblau-demo.xml` and define a libvirt
    domain named `himmelblau-demo` with SPICE graphics, virtio GPU with GL,
    and a vTPM backed by `swtpm`. SSH is forwarded from the host port
    `10022` to the guest port `22` using libvirt's `passt` backend.

5.  **Run the Virtual Machine**

    Start the VM via `virsh` (or your preferred libvirt frontend):

    ```bash
    virsh start himmelblau-demo
    ```

    You can then connect using `virt-viewer`:

    ```bash
    virt-viewer --connect qemu:///system --wait himmelblau-demo
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
